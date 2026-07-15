use std::env;
use std::path::Path;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=target/rel");

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
    }

    tauri_build::build()
}

fn strip_gz_files(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();

        if path.is_dir() {
            strip_gz_files(&path);
        } else if path.extension().is_some_and(|ext| ext == "gz") {
            let _ = std::fs::remove_file(path);
        }
    }
}
