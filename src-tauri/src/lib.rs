// Removes MSVC linker warnings (Windows)
#![allow(linker_messages)]
// On Windows we need to use a nightly rustc version,
// because the feature is not stabilized yet
// https://github.com/rust-lang/rust/issues/127544
// https://github.com/rust-lang/rust/issues/157849
#![cfg_attr(nightly, feature(windows_process_extensions_show_window))]

use base64::Engine;
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;

#[cfg(target_os = "android")]
mod android_beam;
#[cfg(target_os = "android")]
mod android_runtime;

/// Show a native save dialog and write the given base64-encoded contents.
/// Returns `true` when the file was written, `false` when the user cancelled.
#[tauri::command]
async fn save_file(
    app: tauri::AppHandle,
    default_filename: String,
    contents_base64: String,
) -> Result<bool, String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(contents_base64.as_bytes())
        .map_err(|err| format!("invalid base64 content: {err}"))?;

    let filename = default_filename.clone();
    // blocking_save_file must not run on the UI thread (deadlock with the event loop).
    // Async commands + spawn_blocking keep the dialog off the main thread.
    let file_path = tauri::async_runtime::spawn_blocking(move || {
        let mut dialog = app.dialog().file().set_file_name(&filename);

        if let Some(ext) = extension_of(&filename) {
            let label = ext.to_ascii_uppercase();
            dialog = dialog.add_filter(label, &[ext.as_str()]);
        }

        dialog.blocking_save_file()
    })
    .await
    .map_err(|err| format!("save dialog task failed: {err}"))?;

    let Some(file_path) = file_path else {
        return Ok(false);
    };

    let path = file_path
        .into_path()
        .map_err(|err| format!("could not resolve save path: {err}"))?;

    std::fs::write(&path, &bytes)
        .map_err(|err| format!("failed to write {}: {err}", path.display()))?;

    Ok(true)
}

fn extension_of(filename: &str) -> Option<String> {
    std::path::Path::new(filename)
        .extension()
        .and_then(|ext| ext.to_str())
        .filter(|ext| !ext.is_empty())
        .map(|ext| ext.to_ascii_lowercase())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![save_file])
        .setup(move |app| {
            #[cfg(desktop)]
            app.handle()
                .plugin(tauri_plugin_window_state::Builder::default().build())?;

            let app_handle = app.handle().clone();

            pubsub.subscribe("messages", move |msg| {
                if msg[..6] == *b"ready:" {
                    println!("[rust] {}", String::from_utf8_lossy(msg));
                    create_window(&app_handle, &msg[6..]);
                } else {
                    println!("[rust] {}", String::from_utf8_lossy(msg));
                }
            });

            let app_handle = app.handle().clone();
            let pubsub_url = pubsub.url().to_string();

            tauri::async_runtime::spawn_blocking(move || {
                let sys_locale = tauri_plugin_os::locale().unwrap_or_else(|| "en-GB".to_string())
                    [0..2]
                    .to_string();

                #[cfg(target_os = "android")]
                {
                    run_android_beam(&app_handle, pubsub_url, sys_locale);
                }

                #[cfg(not(target_os = "android"))]
                {
                    let rel_dir = app_handle.path().resource_dir().unwrap().join("rel");

                    if cfg!(debug_assertions) {
                        println!("[rust] release dir={}", rel_dir.to_str().unwrap());
                    }

                    let mut command = elixir_command(&rel_dir, sys_locale);
                    command.env("ELIXIRKIT_PUBSUB", pubsub_url);
                    let status = command.status().expect("failed to start Elixir");

                    app_handle.exit(status.code().unwrap_or(1));
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(target_os = "android")]
fn run_android_beam(app_handle: &tauri::AppHandle, pubsub_url: String, sys_locale: String) {
    let release_root = match android_runtime::ensure_release_extracted(app_handle) {
        Ok(path) => path,
        Err(err) => {
            eprintln!("[rust] android release extract failed: {err}");
            app_handle.exit(1);
            return;
        }
    };

    if cfg!(debug_assertions) {
        println!(
            "[rust] android release root={}",
            release_root.to_str().unwrap_or("?")
        );
    }

    let home = app_handle
        .path()
        .app_data_dir()
        .unwrap_or_else(|_| release_root.clone());

    let log_dir = app_handle
        .path()
        .app_log_dir()
        .unwrap_or_else(|_| home.clone());

    let secret_key_base = random_secret_key_base();

    let env = android_beam::ReleaseEnv {
        pubsub_url,
        secret_key_base,
        locale: sys_locale,
        home,
        log_dir,
    };

    if let Err(err) = android_beam::start_release(&release_root, env) {
        eprintln!("[rust] Android BEAM boot failed: {err}");
        app_handle.exit(1);
        return;
    }

    // VM halted.
    app_handle.exit(0);
}

fn create_window(app_handle: &tauri::AppHandle, endpoint_url: &[u8]) {
    let url = tauri::WebviewUrl::External(
        str::from_utf8(endpoint_url)
            .expect("invalid endpoint url")
            .parse()
            .unwrap(),
    );

    tauri::WebviewWindowBuilder::new(app_handle, "main", url)
        .title("BacView")
        .visible(false)
        .build()
        .unwrap();
}

#[cfg(not(target_os = "android"))]
fn elixir_command(rel_dir: &std::path::Path, sys_locale: String) -> std::process::Command {
    if cfg!(desktop) {
        if cfg!(debug_assertions) {
            let mut command = elixirkit::mix("phx.server", &[]);
            command.current_dir("..");
            command.env("BACVIEW_DESKTOP_LOCALE", sys_locale);
            command
        } else {
            elixir_rel_command(rel_dir, sys_locale)
        }
    } else {
        // If compiling for non-desktop (non-android), always go with the release
        elixir_rel_command(rel_dir, sys_locale)
    }
}

#[cfg(not(target_os = "android"))]
fn elixir_rel_command(rel_dir: &std::path::Path, sys_locale: String) -> std::process::Command {
    let secret_key_base = random_secret_key_base();

    let mut command = elixirkit::release(rel_dir, "bacview");
    command.env("BACVIEW_DESKTOP_LOCALE", sys_locale);
    command.env("PHX_SERVER", "true");
    command.env("PHX_HOST", "127.0.0.1");
    command.env("PORT", "0");
    command.env("SECRET_KEY_BASE", secret_key_base);

    // Hide the console window on Windows
    #[cfg(all(windows, nightly))]
    {
        use std::os::windows::process::CommandExt;
        command.show_window(0);
    }

    if cfg!(debug_assertions) {
        println!(
            "[rust] release command={}",
            command.get_program().to_str().unwrap()
        );
    }

    command
}

fn random_secret_key_base() -> String {
    // Generate 64 cryptographically secure random bytes
    let mut key = [0u8; 64];
    getrandom::getrandom(&mut key).expect("failed to get random bytes from OS");

    // Hex encode (lowercase)
    key.iter().map(|b| format!("{:02x}", b)).collect()
}
