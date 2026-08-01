//! Process-based BEAM boot using a Mix release + Android ERTS.
//!
//! Same entry point as desktop: `elixirkit::release(dir, "bacview")` →
//! `bin/bacview start`. On Android we must invoke the script via
//! `/system/bin/sh` because app-data is not executable (W^X).
//!
//! The release tree is prepared so `erts-*` and OTP system apps come from the
//! Android OTP package (see `android_runtime` + `mix mobile.prepare_release`).

use std::fs::OpenOptions;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Boot the Mix release at `release_root` (blocks until the VM exits).
pub fn start_release(release_root: &Path, env: ReleaseEnv) -> Result<(), String> {
    let release_root = release_root
        .canonicalize()
        .unwrap_or_else(|_| release_root.to_path_buf());

    let script = release_root.join("bin/bacview");
    if !script.is_file() {
        return Err(format!("release script missing: {}", script.display()));
    }

    let _ = std::fs::create_dir_all(&env.log_dir);
    let boot_log = env.log_dir.join("android-beam-boot.log");
    let boot_log_file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&boot_log)
        .map_err(|e| format!("open boot log {}: {e}", boot_log.display()))?;
    let boot_err_file = boot_log_file
        .try_clone()
        .map_err(|e| format!("clone boot log: {e}"))?;

    // Mirror elixirkit::release(dir, "bacview") which runs `bin/bacview start`.
    // W^X: cannot exec scripts from app data; run through system sh.
    let mut cmd = Command::new("/system/bin/sh");
    cmd.arg(&script).arg("start");
    cmd.current_dir(&release_root);
    cmd.stdout(Stdio::from(boot_log_file));
    cmd.stderr(Stdio::from(boot_err_file));

    cmd.env("BACVIEW_DESKTOP_LOCALE", &env.locale);
    cmd.env("PHX_SERVER", "true");
    cmd.env("PHX_HOST", "127.0.0.1");
    cmd.env("PORT", "0");
    cmd.env("SECRET_KEY_BASE", &env.secret_key_base);
    cmd.env("ELIXIRKIT_PUBSUB", &env.pubsub_url);
    cmd.env("ELIXIR_DESKTOP_OS", "android");
    cmd.env("HOME", &env.home);
    cmd.env("LOG_DIR", &env.log_dir);
    cmd.env(
        "BACVIEW_LOG_PATH",
        env.log_dir.join("bacview.log").to_string_lossy().as_ref(),
    );

    // Android OTP `erl` wrapper honours ERL_ROOTDIR for the Install placeholder path.
    cmd.env("ERL_ROOTDIR", &release_root);
    cmd.env("ROOTDIR", &release_root);

    // Optional extra emulator flags (do not default to `+J false` — on OTP 27
    // erlexec rejects that and beam.smp only prints Usage then exits 1).
    if let Ok(aflags) = std::env::var("BACVIEW_ERL_AFLAGS") {
        if !aflags.is_empty() {
            cmd.env("ERL_AFLAGS", aflags);
        }
    }

    // Ensure erts bin (with jniLib symlinks for beam.smp/erlexec) is first on PATH.
    if let Some(erts_bin) = find_erts_bin(&release_root) {
        let path = std::env::var("PATH").unwrap_or_default();
        cmd.env("PATH", format!("{}:{}", erts_bin.display(), path));
        cmd.env("BINDIR", &erts_bin);
        // Preflight: helpers must be present (symlinks into nativeLibraryDir).
        for helper in ["erlexec", "beam.smp", "erl_child_setup"] {
            let p = erts_bin.join(helper);
            if !p.exists() {
                return Err(format!(
                    "erts helper missing before boot: {} (jniLibs / W^X packaging)",
                    p.display()
                ));
            }
        }
        println!("[rust] erts BINDIR={}", erts_bin.display());
    } else {
        return Err("no erts-*/bin under release root".to_string());
    }

    println!(
        "[rust] elixirkit-style release start: sh {} start (root={}, boot_log={})",
        script.display(),
        release_root.display(),
        boot_log.display()
    );

    let status = cmd.status().map_err(|e| format!("spawn release: {e}"))?;

    if status.success() {
        Ok(())
    } else {
        let full = std::fs::read_to_string(&boot_log).unwrap_or_default();
        let lines: Vec<&str> = full.lines().collect();
        let start = lines.len().saturating_sub(40);
        let tail = lines[start..].join("\n");
        Err(format!(
            "release exited with {status}; last boot log lines:\n{tail}\n(full log: {})",
            boot_log.display()
        ))
    }
}

pub struct ReleaseEnv {
    pub pubsub_url: String,
    pub secret_key_base: String,
    pub locale: String,
    pub home: PathBuf,
    pub log_dir: PathBuf,
}

fn find_erts_bin(release_root: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(release_root).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with("erts-") {
            let bin = entry.path().join("bin");
            if bin.join("erlexec").is_file() || bin.join("erl").is_file() {
                return Some(bin);
            }
        }
    }
    None
}
