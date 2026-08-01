//! First-run extraction of Mix release + Android ERTS into app data.
//!
//! Assets:
//! - `app-release.zip` — Mix release (`bin/bacview`, `lib/`, `releases/`) without host erts
//! - `erts-{abi}.zip` — full Android OTP install (erts + OTP system apps + NIFs)
//!
//! Merge: Mix release base → overlay Android `erts-*` and OTP system apps →
//! symlink ERTS helpers from `nativeLibraryDir` (W^X) → refresh ERTS_BIN in scripts.

use std::fs::{self, File};
use std::io::{self, Cursor};
use std::path::{Path, PathBuf};

use tauri::Manager;

const RELEASE_MARKER: &str = "done";
const RELEASE_SUBDIR: &str = "app";
const APP_RELEASE_ZIP: &str = "app-release.zip";

/// OTP applications provided by the Android ERTS package (replace host copies).
const ANDROID_OTP_APPS: &[&str] = &[
    "asn1",
    "common_test",
    "compiler",
    "crypto",
    "debugger",
    "dialyzer",
    "diameter",
    "edoc",
    "eldap",
    "erl_interface",
    "erts",
    "et",
    "eunit",
    "ftp",
    "inets",
    "jinterface",
    "kernel",
    "megaco",
    "mnesia",
    "observer",
    "os_mon",
    "parsetools",
    "public_key",
    "reltool",
    "runtime_tools",
    "sasl",
    "snmp",
    "ssh",
    "ssl",
    "stdlib",
    "syntax_tools",
    "tftp",
    "tools",
    "xmerl",
];

/// Ensures the merged release is available under app data and returns its root.
pub fn ensure_release_extracted(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let data_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app_data_dir: {e}"))?;

    let release_root = data_dir.join(RELEASE_SUBDIR);
    let marker = release_root.join(RELEASE_MARKER);
    let abi = android_abi();
    let erts_asset = format!("erts-{abi}.zip");

    // Read ERTS asset first so the stamp includes runtime identity (OTP/erts
    // version + zip size). App version alone is not enough: upgrading from a
    // foreign OTP 28 zip to host-matched OTP 27 with the same APK versionCode
    // would otherwise keep the old extract and crash immediately on device.
    let erts_bytes =
        read_android_asset(&erts_asset).map_err(|e| format!("read {erts_asset}: {e}"))?;
    let erts_meta = erts_zip_meta(&erts_bytes)?;
    let version_stamp = release_stamp(
        &app.package_info().version.to_string(),
        abi,
        &erts_meta,
        erts_bytes.len(),
    );

    if marker.is_file() {
        match fs::read_to_string(&marker) {
            Ok(existing) if existing.trim() == version_stamp => {
                if release_looks_valid(&release_root)
                    && extracted_erts_matches(&release_root, &erts_meta.erts_vsn)
                {
                    // nativeLibraryDir can change after reinstall — refresh symlinks.
                    link_erts_helpers_from_native_libs(&release_root)?;
                    println!(
                        "[rust] reusing release at {} (stamp ok, erts-{})",
                        release_root.display(),
                        erts_meta.erts_vsn
                    );
                    return Ok(release_root);
                }
                eprintln!(
                    "[rust] release marker matches but tree invalid or erts mismatch; re-extracting"
                );
            }
            Ok(existing) => {
                eprintln!(
                    "[rust] release stamp changed ({} → {}); re-extracting",
                    existing.trim(),
                    version_stamp
                );
            }
            _ => {
                eprintln!("[rust] release marker unreadable; re-extracting");
            }
        }
        let _ = fs::remove_dir_all(&release_root);
    } else if release_root.exists() {
        let _ = fs::remove_dir_all(&release_root);
    }

    fs::create_dir_all(&release_root).map_err(|e| format!("mkdir release: {e}"))?;

    // 1) Mix release (bin/bacview, lib app beams, releases/*)
    let app_bytes =
        read_android_asset(APP_RELEASE_ZIP).map_err(|e| format!("read {APP_RELEASE_ZIP}: {e}"))?;
    let staging = data_dir.join("mix_rel_staging");
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging).map_err(|e| format!("mkdir staging: {e}"))?;
    extract_zip_bytes(&app_bytes, &staging).map_err(|e| format!("extract app zip: {e}"))?;

    let mix_root = if staging.join("rel").is_dir() {
        staging.join("rel")
    } else {
        staging.clone()
    };
    copy_dir_recursive(&mix_root, &release_root).map_err(|e| format!("copy mix release: {e}"))?;

    // 2) Android ERTS + OTP system apps
    let erts_staging = data_dir.join("erts_staging");
    let _ = fs::remove_dir_all(&erts_staging);
    fs::create_dir_all(&erts_staging).map_err(|e| format!("mkdir erts staging: {e}"))?;
    extract_zip_bytes(&erts_bytes, &erts_staging)
        .map_err(|e| format!("extract {erts_asset}: {e}"))?;

    merge_android_erts(&erts_staging, &release_root)?;
    let _ = fs::remove_dir_all(&erts_staging);
    let _ = fs::remove_dir_all(&staging);

    strip_gz_files(&release_root);
    link_erts_helpers_from_native_libs(&release_root)?;
    patch_release_scripts_erts_bin(&release_root)?;

    if !release_looks_valid(&release_root) {
        return Err(format!(
            "merged release incomplete at {} (need bin/bacview, erts-*/bin, releases/)",
            release_root.display()
        ));
    }

    fs::write(&marker, &version_stamp).map_err(|e| format!("write marker: {e}"))?;
    println!(
        "[rust] extracted release {} (OTP {}, erts-{}, abi={}, zip {} bytes)",
        release_root.display(),
        erts_meta.otp_version,
        erts_meta.erts_vsn,
        abi,
        erts_bytes.len()
    );
    Ok(release_root)
}

struct ErtsZipMeta {
    erts_vsn: String,
    otp_version: String,
}

fn release_stamp(app_version: &str, abi: &str, meta: &ErtsZipMeta, zip_len: usize) -> String {
    format!(
        "v1|{app_version}|{abi}|erts-{}|otp-{}|zip-{zip_len}",
        meta.erts_vsn, meta.otp_version
    )
}

fn erts_zip_meta(bytes: &[u8]) -> Result<ErtsZipMeta, String> {
    let reader = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader).map_err(|e| format!("open erts zip: {e}"))?;

    let mut erts_vsn: Option<String> = None;
    let mut otp_version = String::from("unknown");

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("erts zip entry: {e}"))?;
        let name = file.name().to_string();

        if erts_vsn.is_none() {
            if let Some(v) = name.strip_prefix("erts-") {
                let vsn = v.split('/').next().unwrap_or("").to_string();
                if !vsn.is_empty() {
                    erts_vsn = Some(vsn);
                }
            }
        }

        if name.ends_with("OTP_VERSION") {
            let mut buf = String::new();
            use std::io::Read;
            file.read_to_string(&mut buf)
                .map_err(|e| format!("read OTP_VERSION: {e}"))?;
            otp_version = buf.trim().to_string();
        }
    }

    let erts_vsn = erts_vsn.ok_or_else(|| "erts zip has no erts-* directory".to_string())?;
    Ok(ErtsZipMeta {
        erts_vsn,
        otp_version,
    })
}

fn extracted_erts_matches(release_root: &Path, expected_erts_vsn: &str) -> bool {
    match find_erts_dir(release_root) {
        Some(dir) => dir
            .file_name()
            .and_then(|s| s.to_str())
            .is_some_and(|n| n == format!("erts-{expected_erts_vsn}")),
        None => false,
    }
}

fn release_looks_valid(root: &Path) -> bool {
    root.join("bin/bacview").is_file()
        && root.join("releases/start_erl.data").is_file()
        && find_erts_dir(root).is_some()
}

fn find_erts_dir(root: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(root).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("erts-") && entry.path().join("bin").is_dir() {
            return Some(entry.path());
        }
    }
    None
}

fn android_abi() -> &'static str {
    match std::env::consts::ARCH {
        "aarch64" => "arm64-v8a",
        "arm" => "armeabi-v7a",
        "x86_64" => "x86_64",
        other => {
            eprintln!(
                "[rust] unknown Android ARCH={other:?} (supported: aarch64→arm64-v8a, \
                 arm→armeabi-v7a, x86_64→x86_64); defaulting to arm64-v8a — \
                 expected asset erts-arm64-v8a.zip"
            );
            "arm64-v8a"
        }
    }
}

/// Copy Android `erts-*` and replace OTP system apps under `lib/`.
fn merge_android_erts(erts_root: &Path, release_root: &Path) -> Result<(), String> {
    // erts-16.2 (or whatever the zip contains)
    let erts_dir = find_erts_dir(erts_root)
        .ok_or_else(|| "Android ERTS zip has no erts-* directory".to_string())?;
    let erts_name = erts_dir
        .file_name()
        .ok_or_else(|| "bad erts dir name".to_string())?;
    let dest_erts = release_root.join(erts_name);

    // Drop any leftover host erts dirs
    if let Ok(entries) = fs::read_dir(release_root) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with("erts-") {
                let _ = fs::remove_dir_all(entry.path());
            }
        }
    }

    copy_dir_recursive(&erts_dir, &dest_erts).map_err(|e| format!("copy erts: {e}"))?;

    // OTP system apps from Android lib/
    let android_lib = erts_root.join("lib");
    let dest_lib = release_root.join("lib");
    fs::create_dir_all(&dest_lib).map_err(|e| format!("mkdir lib: {e}"))?;

    if android_lib.is_dir() {
        for entry in fs::read_dir(&android_lib)
            .map_err(|e| format!("read android lib: {e}"))?
            .flatten()
        {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if !is_android_otp_app(&name_str) {
                continue;
            }
            // Remove any host version of this app (different -vsn dir names).
            remove_lib_app_versions(&dest_lib, app_name_from_dir(&name_str))?;
            let to = dest_lib.join(&name);
            copy_dir_recursive(&entry.path(), &to)
                .map_err(|e| format!("overlay lib/{name_str}: {e}"))?;
        }
    }

    // Also copy top-level bin helpers from Android install if present (erl scripts).
    let android_bin = erts_root.join("bin");
    if android_bin.is_dir() {
        let dest_bin = release_root.join("bin");
        fs::create_dir_all(&dest_bin).map_err(|e| format!("mkdir bin: {e}"))?;
        for name in ["start_clean.boot", "start.boot", "no_dot_erlang.boot"] {
            let from = android_bin.join(name);
            if from.is_file() {
                let _ = fs::copy(&from, dest_bin.join(name));
            }
        }
    }

    // start_erl.data: Android erts vsn + Mix app vsn
    let erts_vsn = erts_name
        .to_str()
        .and_then(|s| s.strip_prefix("erts-"))
        .unwrap_or("16.2");
    let app_vsn = detect_app_version(release_root).unwrap_or_else(|| "0.1.0".to_string());
    fs::write(
        release_root.join("releases/start_erl.data"),
        format!("{erts_vsn} {app_vsn}\n"),
    )
    .map_err(|e| format!("write start_erl.data: {e}"))?;

    Ok(())
}

fn app_name_from_dir(dir_name: &str) -> &str {
    dir_name.split('-').next().unwrap_or(dir_name)
}

fn is_android_otp_app(dir_name: &str) -> bool {
    let app = app_name_from_dir(dir_name);
    ANDROID_OTP_APPS.contains(&app)
}

fn remove_lib_app_versions(lib_dir: &Path, app: &str) -> Result<(), String> {
    let Ok(entries) = fs::read_dir(lib_dir) else {
        return Ok(());
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if app_name_from_dir(&name_str) == app {
            let _ = fs::remove_dir_all(entry.path());
        }
    }
    Ok(())
}

fn detect_app_version(root: &Path) -> Option<String> {
    let rel = root.join("releases");
    let entries = fs::read_dir(rel).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if entry.path().join("sys.config").is_file() {
            return Some(name.to_string());
        }
    }
    None
}

/// Point `releases/*/elixir` and `iex` ERTS_BIN at the Android erts dir.
fn patch_release_scripts_erts_bin(release_root: &Path) -> Result<(), String> {
    let erts_dir =
        find_erts_dir(release_root).ok_or_else(|| "no erts-* after merge".to_string())?;
    let erts_name = erts_dir
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| "bad erts name".to_string())?;

    let rel = release_root.join("releases");
    let entries = fs::read_dir(&rel).map_err(|e| format!("read releases: {e}"))?;
    for entry in entries.flatten() {
        if !entry.path().is_dir() {
            continue;
        }
        for script_name in ["elixir", "iex"] {
            let script = entry.path().join(script_name);
            if !script.is_file() {
                continue;
            }
            let contents = fs::read_to_string(&script)
                .map_err(|e| format!("read {}: {e}", script.display()))?;
            // Release scripts embed: ERTS_BIN="$SCRIPT_PATH"/../../erts-X.Y.Z/bin/
            let patched = replace_erts_bin_line(&contents, erts_name);
            if patched != contents {
                fs::write(&script, patched)
                    .map_err(|e| format!("write {}: {e}", script.display()))?;
                println!(
                    "[rust] patched ERTS_BIN in {} → {}",
                    script.display(),
                    erts_name
                );
            }
        }
    }
    Ok(())
}

fn replace_erts_bin_line(contents: &str, erts_name: &str) -> String {
    let mut out = String::with_capacity(contents.len());
    for line in contents.lines() {
        if line.trim_start().starts_with("ERTS_BIN=") && line.contains("erts-") {
            // Preserve indentation and the $SCRIPT_PATH form used by Mix releases.
            let indent = line.len() - line.trim_start().len();
            out.push_str(&" ".repeat(indent));
            out.push_str("ERTS_BIN=\"$SCRIPT_PATH\"/../../");
            out.push_str(erts_name);
            out.push_str("/bin/");
            out.push('\n');
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

/// Symlink ERTS helpers to jniLibs copies (`lib__*.so`) so they are executable.
fn link_erts_helpers_from_native_libs(release_root: &Path) -> Result<(), String> {
    let native_dir = native_library_dir()?;
    let erts_dir =
        find_erts_dir(release_root).ok_or_else(|| "no erts-* after extract".to_string())?;
    let bin = erts_dir.join("bin");
    fs::create_dir_all(&bin).map_err(|e| format!("mkdir erts bin: {e}"))?;

    let links = [
        ("beam.smp", "lib__beam_smp.so"),
        ("erlexec", "lib__erlexec.so"),
        ("erl_child_setup", "lib__erl_child_setup.so"),
        ("inet_gethost", "lib__inet_gethost.so"),
    ];

    for (bin_name, jni_name) in links {
        let target = native_dir.join(jni_name);
        if !target.is_file() {
            return Err(format!(
                "native helper missing: {} (package lib__*.so in jniLibs + useLegacyPackaging)",
                target.display()
            ));
        }
        let link = bin.join(bin_name);
        let _ = fs::remove_file(&link);
        std::os::unix::fs::symlink(&target, &link)
            .map_err(|e| format!("symlink {} → {}: {e}", link.display(), target.display()))?;
        println!("[rust] linked {} → {}", link.display(), target.display());
    }

    Ok(())
}

fn native_library_dir() -> Result<PathBuf, String> {
    use std::sync::mpsc;

    let (tx, rx) = mpsc::channel();
    tauri::wry::prelude::dispatch(move |env, activity, _webview| {
        let result = (|| -> Result<PathBuf, String> {
            let app_info = env
                .call_method(
                    activity,
                    "getApplicationInfo",
                    "()Landroid/content/pm/ApplicationInfo;",
                    &[],
                )
                .map_err(|e| format!("getApplicationInfo: {e}"))?
                .l()
                .map_err(|e| format!("ApplicationInfo: {e}"))?;

            let field = env
                .get_field(&app_info, "nativeLibraryDir", "Ljava/lang/String;")
                .map_err(|e| format!("nativeLibraryDir field: {e}"))?
                .l()
                .map_err(|e| format!("nativeLibraryDir jobject: {e}"))?;

            let jstr = jni::objects::JString::from(field);
            let path: String = env
                .get_string(&jstr)
                .map_err(|e| format!("nativeLibraryDir string: {e}"))?
                .into();
            Ok(PathBuf::from(path))
        })();
        let _ = tx.send(result);
    });

    match rx.recv() {
        Ok(r) => r,
        Err(e) => Err(format!("nativeLibraryDir dispatch: {e}")),
    }
}

fn read_android_asset(name: &str) -> Result<Vec<u8>, String> {
    use std::sync::mpsc;

    let (tx, rx) = mpsc::channel();
    let asset_name = name.to_string();

    tauri::wry::prelude::dispatch(move |env, activity, _webview| {
        let result = read_asset_with_env(env, activity, &asset_name);
        let _ = tx.send(result);
    });

    match rx.recv() {
        Ok(result) => result,
        Err(err) => Err(format!("android asset dispatch: {err}")),
    }
}

fn read_asset_with_env(
    env: &mut jni::JNIEnv,
    activity: &jni::objects::JObject,
    name: &str,
) -> Result<Vec<u8>, String> {
    let asset_manager = env
        .call_method(
            activity,
            "getAssets",
            "()Landroid/content/res/AssetManager;",
            &[],
        )
        .map_err(|e| format!("getAssets: {e}"))?
        .l()
        .map_err(|e| format!("getAssets jobject: {e}"))?;

    let jname = env
        .new_string(name)
        .map_err(|e| format!("new_string: {e}"))?;

    let input_stream = env
        .call_method(
            &asset_manager,
            "open",
            "(Ljava/lang/String;)Ljava/io/InputStream;",
            &[(&jname).into()],
        )
        .map_err(|e| format!("AssetManager.open({name}): {e}"))?
        .l()
        .map_err(|e| format!("open jobject: {e}"))?;

    let mut out = Vec::new();
    let buf = env
        .new_byte_array(64 * 1024)
        .map_err(|e| format!("byte array: {e}"))?;

    loop {
        let n = env
            .call_method(
                &input_stream,
                "read",
                "([B)I",
                &[jni::objects::JValue::Object(&buf)],
            )
            .map_err(|e| format!("InputStream.read: {e}"))?
            .i()
            .map_err(|e| format!("read int: {e}"))?;

        if n <= 0 {
            break;
        }

        let chunk = env
            .convert_byte_array(&buf)
            .map_err(|e| format!("convert_byte_array: {e}"))?;
        out.extend_from_slice(&chunk[..n as usize]);
    }

    let _ = env.call_method(&input_stream, "close", "()V", &[]);

    if out.is_empty() {
        return Err(format!("asset {name} empty or missing"));
    }

    Ok(out)
}

fn extract_zip_bytes(bytes: &[u8], dest_parent: &Path) -> io::Result<()> {
    let reader = Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let outpath = match file.enclosed_name() {
            Some(path) => dest_parent.join(path),
            None => continue,
        };

        if file.name().ends_with('/') {
            fs::create_dir_all(&outpath)?;
        } else {
            if let Some(parent) = outpath.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut outfile = File::create(&outpath)?;
            io::copy(&mut file, &mut outfile)?;
        }
    }

    Ok(())
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let from = entry.path();
        let to = dst.join(entry.file_name());

        if file_type.is_dir() {
            copy_dir_recursive(&from, &to)?;
        } else if file_type.is_file() {
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&from, &to)?;
        }
    }

    Ok(())
}

fn strip_gz_files(dir: &Path) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            strip_gz_files(&path);
        } else if path.extension().is_some_and(|ext| ext == "gz") {
            let _ = fs::remove_file(path);
        }
    }
}
