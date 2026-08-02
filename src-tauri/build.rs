use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=target/rel");
    // Host-matched trees under priv/runtimes/android/otp{27,28,29}/
    for major in ["27", "28", "29"] {
        for abi in ["x86_64", "arm64-v8a", "armeabi-v7a"] {
            println!("cargo:rerun-if-changed=../priv/runtimes/android/otp{major}/erts-{abi}.zip");
        }
    }

    // Tell rustc that "nightly" is a valid custom cfg we control.
    // This silences the "unexpected cfg condition name" warning.
    println!("cargo::rustc-check-cfg=cfg(nightly)");

    let rustc = env::var("RUSTC").unwrap_or_else(|_| "rustc".to_string());

    let output = Command::new(&rustc)
        .arg("--version")
        .output()
        .expect("failed to execute rustc");

    let version = String::from_utf8_lossy(&output.stdout);

    if version.contains("nightly") {
        println!("cargo:rustc-cfg=nightly");
    }

    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        // phx.digest writes both file and file.gz; Android's asset merger rejects those pairs.
        strip_gz_files(Path::new("target/rel"));
        strip_gz_files(Path::new("gen/android/app/src/main/assets/rel"));
        // Process-based Android OTP (erts-*.zip) — no static liberlang link.
        // Stage *all* ABIs: tauri.conf.json lists every erts-*.zip as a resource, and
        // universal APKs need them even when this cargo invocation is single-ABI.
        stage_android_erts_assets();
        // Android 10+ W^X: cannot exec binaries from app data; package helpers as jniLibs.
        stage_erts_helpers_as_jni_libs();
    }

    // tauri.conf.json lists these resources; create placeholders so cargo/tauri do not
    // fail when target/ was cleaned or only one ABI has been staged yet.
    ensure_app_release_zip_placeholder();
    ensure_erts_zip_placeholders();

    // Autogenerate allow-save-file / deny-save-file so the Phoenix webview
    // (loaded as http://127.0.0.1 — a remote origin) can invoke save_file.
    tauri_build::try_build(
        tauri_build::Attributes::new()
            .app_manifest(tauri_build::AppManifest::new().commands(&["save_file"])),
    )
    .expect("failed to run tauri-build")
}

const EMPTY_ZIP: [u8; 22] = [
    0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

const ANDROID_ERTS_ABIS: &[&str] = &["x86_64", "arm64-v8a", "armeabi-v7a"];

fn ensure_app_release_zip_placeholder() {
    let zip_path = Path::new("target/app-release.zip");
    if zip_path.is_file() {
        return;
    }
    if let Some(parent) = zip_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(zip_path, EMPTY_ZIP);
}

/// Ensure `target/erts-{abi}.zip` exist for every ABI listed in tauri.conf.json.
fn ensure_erts_zip_placeholders() {
    let _ = fs::create_dir_all("target");
    for abi in ANDROID_ERTS_ABIS {
        let dest = Path::new("target").join(format!("erts-{abi}.zip"));
        if dest.is_file() {
            continue;
        }
        let _ = fs::write(&dest, EMPTY_ZIP);
        println!(
            "cargo:warning=placeholder {} (no real ERTS staged yet; \
             run ./scripts/build_android_otp.sh <major> and rebuild Android)",
            dest.display()
        );
    }
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

/// Maps `CARGO_CFG_TARGET_ARCH` → Android ABI name used in `erts-{abi}.zip`.
/// Returns `(arch, abi)` or `(arch, None)` when unsupported.
fn target_arch_and_abi() -> (String, Option<&'static str>) {
    let arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| "<unset>".to_string());
    let abi = match arch.as_str() {
        "aarch64" => Some("arm64-v8a"),
        "arm" => Some("armeabi-v7a"),
        "x86_64" => Some("x86_64"),
        // i686 Android is rare; call it out explicitly if seen.
        "x86" | "i686" => None,
        _ => None,
    };
    (arch, abi)
}

/// Host OTP major from `erl` (e.g. `"27"`). Empty if erl is unavailable.
fn host_otp_major() -> String {
    let output = Command::new("erl")
        .args([
            "-noshell",
            "-eval",
            r#"io:format("~s",[erlang:system_info(otp_release)]),halt()."#,
        ])
        .output();
    match output {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        _ => String::new(),
    }
}

/// `priv/runtimes/android/otp{major}/erts-{abi}.zip` for the host OTP major only.
fn android_erts_zip_src(abi: &str) -> Option<std::path::PathBuf> {
    let major = host_otp_major();
    if major.is_empty() {
        return None;
    }
    let name = format!("erts-{abi}.zip");
    let p = Path::new("../priv/runtimes/android")
        .join(format!("otp{major}"))
        .join(name);
    if p.is_file() {
        Some(p)
    } else {
        None
    }
}

/// Stage host-matched Android ERTS into `target/` for tauri bundle resources.
///
/// Copies **every** ABI that exists under `otp{host_major}/`, not only the
/// current `CARGO_CFG_TARGET_ARCH`. Universal Android builds invoke cargo once
/// per ABI, but `tauri.conf.json` always requires all three resource paths.
fn stage_android_erts_assets() {
    let major = host_otp_major();
    if major.is_empty() {
        println!(
            "cargo:warning=cannot detect host OTP major (is erl on PATH?); \
             ERTS zips not staged from priv/runtimes/android/otp*/"
        );
        return;
    }

    let _ = fs::create_dir_all("target");
    let mut staged = 0usize;

    for abi in ANDROID_ERTS_ABIS {
        let Some(src) = android_erts_zip_src(abi) else {
            println!(
                "cargo:warning=Android ERTS zip missing for host OTP {major} ABI={abi} — \
                 need priv/runtimes/android/otp{major}/erts-{abi}.zip \
                 (./scripts/build_android_otp.sh {major} {abi})"
            );
            continue;
        };
        let src_len = src.metadata().map(|m| m.len()).unwrap_or(0);
        if src_len < 1024 {
            println!(
                "cargo:warning=Android ERTS zip empty/placeholder at {} ({} bytes)",
                src.display(),
                src_len
            );
            continue;
        }

        let dest = Path::new("target").join(format!("erts-{abi}.zip"));
        if let Err(err) = fs::copy(&src, &dest) {
            panic!("failed to stage {}: {err}", src.display());
        }
        staged += 1;
        println!(
            "cargo:warning=staged Android ERTS {} → {} (host OTP {major})",
            src.display(),
            dest.display()
        );
        println!("cargo:rerun-if-changed={}", src.display());
    }

    if staged == 0 {
        println!(
            "cargo:warning=no Android ERTS zips staged for host OTP {major} — \
             APK first launch will fail. Build with: ./scripts/build_android_otp.sh {major}"
        );
    }

    let (arch, this_abi) = target_arch_and_abi();
    if this_abi.is_none() {
        println!(
            "cargo:warning=unsupported Android TARGET_ARCH={arch:?} for jniLibs helpers \
             (supported: aarch64, arm, x86_64)"
        );
    }
}

/// Package ERTS executables as `lib__*.so` under jniLibs so Android 10+ allows exec
/// (native library dir is executable; app-private data is not — W^X).
///
/// At runtime we symlink `erts-*/bin/{name}` → `nativeLibraryDir/lib__{name}.so`.
fn stage_erts_helpers_as_jni_libs() {
    let (arch, abi) = target_arch_and_abi();
    let Some(abi) = abi else {
        println!(
            "cargo:warning=skip jniLibs ERTS helpers: unsupported TARGET_ARCH={arch:?} \
             (supported: aarch64, arm, x86_64)"
        );
        return;
    };

    let major = host_otp_major();
    let Some(zip_path) = android_erts_zip_src(abi) else {
        println!(
            "cargo:warning=skip jniLibs ERTS helpers for TARGET_ARCH={arch} ABI={abi}: \
             no host-matched erts zip (host OTP {major:?}; \
             ./scripts/build_android_otp.sh {{N}} {abi})"
        );
        return;
    };
    let zip_len = zip_path.metadata().map(|m| m.len()).unwrap_or(0);
    if zip_len < 1024 {
        println!(
            "cargo:warning=skip jniLibs ERTS helpers for TARGET_ARCH={arch} ABI={abi}: \
             empty {} ({} bytes; ./scripts/build_android_otp.sh {major} {abi})",
            zip_path.display(),
            zip_len
        );
        return;
    }

    let jni_dir = Path::new("gen/android/app/src/main/jniLibs").join(abi);
    fs::create_dir_all(&jni_dir).expect("create jniLibs dir");

    // (zip member path suffix, jni lib name)
    // beam.smp → lib__beam_smp.so (dot not allowed in jni names)
    let helpers = [
        ("erts-", "/bin/beam.smp", "lib__beam_smp.so"),
        ("erts-", "/bin/erlexec", "lib__erlexec.so"),
        ("erts-", "/bin/erl_child_setup", "lib__erl_child_setup.so"),
        ("erts-", "/bin/inet_gethost", "lib__inet_gethost.so"),
    ];

    // List zip members once
    let list = Command::new("unzip")
        .args(["-Z1", zip_path.to_str().unwrap()])
        .output()
        .expect("unzip -Z1 erts zip");
    let listing = String::from_utf8_lossy(&list.stdout);

    for (prefix, suffix, jni_name) in helpers {
        let member = listing
            .lines()
            .find(|line| line.contains(prefix) && line.ends_with(suffix));
        let Some(member) = member else {
            println!("cargo:warning=erts zip missing member *{suffix}");
            continue;
        };

        let dest = jni_dir.join(jni_name);
        // Extract single file to a temp name then rename
        let status = Command::new("unzip")
            .args([
                "-o",
                "-j",
                zip_path.to_str().unwrap(),
                member,
                "-d",
                jni_dir.to_str().unwrap(),
            ])
            .status()
            .expect("unzip helper from erts zip");
        if !status.success() {
            panic!("failed to extract {member} from {}", zip_path.display());
        }

        // unzip -j drops to basename (e.g. beam.smp)
        let basename = Path::new(member).file_name().unwrap().to_str().unwrap();
        let extracted = jni_dir.join(basename);
        if extracted != dest {
            let _ = fs::remove_file(&dest);
            fs::rename(&extracted, &dest).unwrap_or_else(|e| {
                panic!("rename {} → {}: {e}", extracted.display(), dest.display());
            });
        }
        println!("cargo:warning=staged jni helper {}", dest.display());
    }
}
