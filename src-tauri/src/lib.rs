use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let pubsub = elixirkit::PubSub::listen("tcp://127.0.0.1:0").expect("failed to listen");

    tauri::Builder::default()
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
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

            tauri::async_runtime::spawn_blocking(move || {
                let rel_dir = app_handle.path().resource_dir().unwrap().join("rel");
                let mut command = elixir_command(&rel_dir);
                command.env("ELIXIRKIT_PUBSUB", pubsub.url());
                let status = command.status().expect("failed to start Elixir");

                app_handle.exit(status.code().unwrap_or(1));
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn create_window(app_handle: &tauri::AppHandle, endpoint_url: &[u8]) {
    let n = app_handle.webview_windows().len() + 1;
    let url = tauri::WebviewUrl::External(
        str::from_utf8(endpoint_url)
            .expect("invalid endpoint url")
            .parse()
            .unwrap(),
    );

    // 1. Create the window with a safe default size
    let window = tauri::WebviewWindowBuilder::new(app_handle, format!("window-{}", n), url)
        .title("BacView")
        .inner_size(1280.0, 800.0)
        .build()
        .unwrap();

    // 2. Get monitor work area and resize to 90%
    if let Ok(Some(monitor)) = window.current_monitor() {
        let work_area = monitor.work_area(); // excludes taskbar/dock
        let physical: tauri::PhysicalSize<u32> = work_area.size;
        let scale_factor = monitor.scale_factor();

        // 90% of usable screen area in logical pixels
        let logical_width = (physical.width as f64 / scale_factor) * 0.9;
        let logical_height = (physical.height as f64 / scale_factor) * 0.9;

        let _ = window.set_size(tauri::LogicalSize::new(logical_width, logical_height));
        let _ = window.center(); // re-center after resize
    }
    // If monitor detection fails, window stays at the default 1280×800 size
}

fn elixir_command(rel_dir: &std::path::Path) -> std::process::Command {
    let sys_locale =
        tauri_plugin_os::locale().unwrap_or_else(|| "en-GB".to_string())[0..2].to_string();

    if cfg!(debug_assertions) {
        let mut command = elixirkit::mix("phx.server", &[]);
        command.current_dir("..");
        command.env("BACVIEW_DESKTOP_LOCALE", sys_locale);
        command
    } else {
        // Generate 64 cryptographically secure random bytes
        let mut key = [0u8; 64];
        getrandom::getrandom(&mut key).expect("failed to get random bytes from OS");

        // Hex encode (lowercase)
        let secret_key_base: String = key.iter().map(|b| format!("{:02x}", b)).collect();

        let mut command = elixirkit::release(rel_dir, "bacview");
        command.env("BACVIEW_DESKTOP_LOCALE", sys_locale);
        command.env("PHX_SERVER", "true");
        command.env("PHX_HOST", "127.0.0.1");
        command.env("PORT", "0");
        command.env("SECRET_KEY_BASE", secret_key_base);
        command
    }
}
