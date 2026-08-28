// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Inject WEBKIT_DISABLE_DMABUF_RENDERER=1 conditionally
    // This fixes a startup crash if running on a NVIDIA GPU
    #[cfg(target_os = "linux")]
    {
        let disable_dmabuf = std::env::args().any(|arg| arg == "--disable-dmabuf-renderer");
        let disable_nv_sync = std::env::args().any(|arg| arg == "--disable-nv-explicit-sync");

        let options = webkit2gtk_nvidia_quirk::ApplyWorkaroundOptions::default()
            .force_disable_dmabuf(disable_dmabuf)
            .force_disable_nv_explicit_sync(disable_nv_sync);

        webkit2gtk_nvidia_quirk::apply_workaround_with_options(options);
    }

    bacview_lib::run()
}
