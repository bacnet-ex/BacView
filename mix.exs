defmodule BacView.MixProject do
  use Mix.Project

  def project() do
    [
      app: :bacview,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      package: package(),
      releases: releases(),
      dialyzer: [
        # Flags could be ["-Wno_opaque"]
        flags: [],
        ignore_warnings: "dialyzer.ignore-warnings.exs",
        plt_add_apps: [:ex_unit, :mix]
      ]
    ]
  end

  def application() do
    [
      mod: {BacView.Application, []},
      extra_applications: [:logger, :runtime_tools] ++ desktop_extra_applications()
    ]
  end

  def cli() do
    [
      preferred_envs: [
        precommit: :test,
        "desktop.prepare_release": :prod,
        "desktop.installer": :prod,
        "mobile.prepare_release": :prod,
        "mobile.android.dev": :prod,
        "mobile.android.build": :prod
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    base_deps() ++ desktop_deps() ++ uart_deps()
  end

  defp base_deps() do
    [
      {:bacstack, github: "bacnet-ex/bacstack", env: Mix.env()},
      {:bacnet_ede, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:gettext, "~> 0.26"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:jason, "~> 1.2"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:req, "~> 0.5"},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:tzdata, "~> 1.1"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp desktop_deps() do
    if desktop_mode?() do
      [{:elixirkit, "~> 0.1.0"}]
    else
      []
    end
  end

  defp uart_deps() do
    if include_circuits_uart?() do
      [{:circuits_uart, "~> 1.5"}]
    else
      []
    end
  end

  defp desktop_extra_applications() do
    if desktop_mode?() do
      [:ssl, :sasl, :tools, :inets]
    else
      []
    end
  end

  defp aliases() do
    cmd_prefix =
      if Version.compare(System.version(), "1.19.0-dev") != :lt do
        " --shell"
      else
        ""
      end

    desktop_env = fn _args ->
      if not desktop_mode?() do
        raise "Missing environment variable BACVIEW_DESKTOP=1 - it is required for desktop/android"
      end
    end

    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind bacview", "esbuild bacview"],
      "assets.deploy": [
        "tailwind bacview --minify",
        "esbuild bacview --minify",
        "phx.digest"
      ],
      "desktop.setup": [
        desktop_env,
        "setup",
        "cmd#{cmd_prefix} cd src-tauri && cargo install tauri-cli --version \"^2.11.4\" --locked || true",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri icon ../priv/static/icon.png"
      ],
      "desktop.server": [
        desktop_env,
        "compile --force",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri dev"
      ],
      "desktop.prepare_release": [
        desktop_env,
        "desktop.setup",
        "assets.deploy",
        "compile --force",
        # Manual tzdata update (automatic is disabled -> readonly fs (i.e. appimage) may not like it)
        "eval \":application.ensure_all_started(:hackney); Tzdata.EtsHolder.start_link([]); Tzdata.ReleaseUpdater.poll_for_update()\"",
        "release --overwrite --path src-tauri/target/rel"
      ],
      "desktop.installer": [
        "desktop.prepare_release",
        # "cmd#{cmd_prefix} cd src-tauri && cargo tauri build --bundles deb"
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri build"
      ],
      # Android: Mix release + host-matched Android OTP ERTS
      # (priv/runtimes/android/otp{N}/erts-{abi}.zip from scripts/build_android_otp.sh).
      "mobile.prepare_release": [
        desktop_env,
        "desktop.setup",
        "assets.deploy",
        "compile --force",
        # Manual tzdata update (automatic is disabled -> readonly fs (i.e. appimage) may not like it)
        "eval \":application.ensure_all_started(:hackney); Tzdata.EtsHolder.start_link([]); Tzdata.ReleaseUpdater.poll_for_update()\"",
        "release --overwrite --path src-tauri/target/rel",
        &strip_release_gz_files/1,
        &ensure_host_matched_android_erts/1,
        &strip_host_erts_for_android/1,
        &patch_android_elixir_scripts/1,
        &patch_bacview_script_for_android/1,
        &zip_release_for_android/1
      ],
      "mobile.android.dev": [
        "mobile.prepare_release",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri android dev"
      ],
      "mobile.android.build": [
        "mobile.prepare_release",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri android build"
      ],
      precommit: [
        "deps.unlock --unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --all",
        "dialyzer",
        "test --warnings-as-errors",
        "cmd#{cmd_prefix} cd src-tauri && cargo fmt --check",
        "cmd#{cmd_prefix} cd src-tauri && cargo clippy --all-targets",
        "cmd#{cmd_prefix} cd src-tauri && cargo test --all-targets"
      ]
    ]
  end

  defp releases() do
    if desktop_mode?() do
      [
        bacview: [
          # Beams are arch-independent. Desktop uses host erts + bin/bacview.
          # Android overlays Elixir/app beams onto a full Android OTP ERTS tree
          # (process-based beam.smp; see mobile.prepare_release).
          include_erts: true,
          include_executables_for: [:windows, :unix],
          applications: [runtime_tools: :permanent, ssl: :permanent],
          # codesign is for MacOS - see elixirkit!
          # &ElixirKit.Release.codesign/1
          steps: [:assemble, &strip_desktop_release_extras/1]
        ]
      ]
    else
      [
        bacview: [
          include_executables_for: [:windows, :unix],
          applications: [runtime_tools: :permanent],
          steps: [:assemble, :tar],
          overlays: ["rel/overlays"]
        ]
      ]
    end
  end

  # Drop bundled Android runtime tarballs from the Mix release (shipped separately
  # as erts-{abi}.zip for mobile). Also strip phx.digest .gz pairs and any
  # local `runtime_settings.json` that was present under priv/ during assemble
  # (must not ship machine-specific stack settings in desktop/mobile packages).
  defp strip_desktop_release_extras(release) do
    release_path = release.path

    release_path
    |> Path.join("lib/*/priv/runtimes")
    |> Path.wildcard()
    |> Enum.each(&File.rm_rf/1)

    strip_runtime_settings_from_release(release_path)
    strip_gz_under(release_path)
    release
  end

  defp strip_runtime_settings_from_release(release_path) when is_binary(release_path) do
    release_path
    |> Path.join("lib/*/priv/runtime_settings.json")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      File.rm(path)
      IO.puts("  stripped #{Path.relative_to_cwd(path)}")
    end)
  end

  # Android asset merger rejects file + file.gz pairs from phx.digest.
  defp strip_release_gz_files(_args) do
    strip_gz_under(Path.expand("src-tauri/target/rel"))
  end

  # Require Android ERTS zips for the same host OTP *major* only (e.g. 27.x).
  # Exact OTP_VERSION need not match: android_runtime rewrites start_erl.data and
  # ERTS_BIN when merging the device ERTS zip; boot uses start_clean.
  defp ensure_host_matched_android_erts(_args) do
    major = host_otp_major()
    base = android_erts_dir_for_major(major)
    zip = android_erts_zip_in(base)

    unless zip do
      raise """
      Missing host-matched Android OTP ERTS for OTP major #{major} (host #{host_otp_version()}).

      Expected at least one of:
        #{Path.join(base, "erts-x86_64.zip")}
        #{Path.join(base, "erts-arm64-v8a.zip")}
        #{Path.join(base, "erts-armeabi-v7a.zip")}

      Build them with (same major as host OTP):
        ./scripts/build_android_otp.sh #{major} x86_64
        ./scripts/build_android_otp#{major}.sh

      See scripts/build_android_otp.sh (OTP 27/28/29).
      """
    end

    android_otp = android_otp_version_from_zip(zip)
    host_otp = host_otp_version()

    if android_otp do
      # Major-only: host 27.2.x may use otp27 zips built as 27.3.x (runtime rewrites erts paths).
      zip_major = android_otp |> String.trim() |> String.split(".", parts: 2) |> List.first()

      if zip_major != major do
        raise """
        Android ERTS OTP major #{zip_major} (zip OTP_VERSION=#{android_otp}) does not match \
        host OTP major #{major} (host #{host_otp}).

        Place zips under priv/runtimes/android/otp#{major}/ or rebuild:

          ./scripts/build_android_otp.sh #{major}

        Zip used: #{zip}
        """
      end
    end

    IO.puts(
      "Android ERTS ok: host major #{major} (#{host_otp || "?"}), " <>
        "zip #{Path.relative_to_cwd(zip)}" <>
        if(android_otp, do: " (OTP #{android_otp})", else: "")
    )
  end

  defp host_otp_major do
    :erlang.system_info(:otp_release) |> List.to_string()
  end

  defp host_otp_version do
    major = host_otp_major()
    path = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    case File.read(path) do
      {:ok, body} -> String.trim(body)
      _ -> major
    end
  end

  defp android_erts_dir_for_major(major) when is_binary(major) do
    Path.expand("priv/runtimes/android/otp#{major}")
  end

  defp android_erts_zip_names,
    do: ["erts-x86_64.zip", "erts-arm64-v8a.zip", "erts-armeabi-v7a.zip"]

  defp android_erts_zip_in(base) do
    Enum.find_value(android_erts_zip_names(), fn name ->
      path = Path.join(base, name)

      if File.exists?(path) and File.stat!(path).size > 1024 do
        path
      end
    end)
  end

  defp android_otp_version_from_zip(zip_path) do
    {listing, 0} = System.cmd("unzip", ["-Z1", zip_path])

    otp_version_member =
      Enum.find(String.split(listing, "\n", trim: true), fn line ->
        String.ends_with?(line, "OTP_VERSION")
      end)

    if otp_version_member do
      {body, 0} = System.cmd("unzip", ["-p", zip_path, otp_version_member])
      String.trim(body)
    else
      nil
    end
  end

  # Host erts + host-arch NIFs must not ship in the Android Mix overlay; the
  # device uses Android OTP ERTS (beam.smp, erl_child_setup, crypto.so, …).
  # Also drop host OTP system apps (kernel/stdlib/crypto/…) — replaced on device
  # from erts-{abi}.zip. Runtime rewrites start_erl.data to the Android erts vsn.
  defp strip_host_erts_for_android(_args) do
    rel = Path.expand("src-tauri/target/rel")

    if File.dir?(rel) do
      rel
      |> Path.join("erts-*")
      |> Path.wildcard()
      |> Enum.each(&File.rm_rf/1)

      # Host-built .so NIFs under lib/*/priv
      rel
      |> Path.join("lib/**/priv/**/*.so")
      |> Path.wildcard()
      |> Enum.each(&File.rm/1)

      rel
      |> Path.join("lib/circuits_uart-*/priv/circuits_uart")
      |> Path.wildcard()
      |> Enum.each(&File.rm/1)

      # Host OTP system apps — Android ERTS zip supplies matching versions.
      for app <- android_otp_app_names() do
        rel
        |> Path.join("lib/#{app}-*")
        |> Path.wildcard()
        |> Enum.each(&File.rm_rf/1)
      end
    end
  end

  defp android_otp_app_names do
    ~w(asn1 compiler crypto inets kernel public_key runtime_tools sasl ssl
      stdlib syntax_tools tools)
  end

  # Android W^X: release scripts under app data cannot be exec'd; use erlexec (jniLib).
  # Device merge also rewrites ERTS_BIN to the Android erts-* directory name.
  defp patch_android_elixir_scripts(_args) do
    rel = Path.expand("src-tauri/target/rel")

    for app_vsn_dir <- Path.wildcard(Path.join(rel, "releases/*")),
        File.dir?(app_vsn_dir),
        name <- ["elixir", "iex"] do
      path = Path.join(app_vsn_dir, name)

      if File.exists?(path) do
        content = File.read!(path)
        patched = String.replace(content, ~s|ERL_EXEC="erl"|, ~s|ERL_EXEC="erlexec"|)

        if patched != content do
          File.write!(path, patched)
          IO.puts("  patched #{Path.relative_to_cwd(path)} (ERL_EXEC=erlexec)")
        end
      end
    end
  end

  # Keep elixirkit entry (`bin/bacview start`) but fix Android constraints:
  # W^X + start via erlexec / start_clean + ensure_all_started (Config.Provider
  # only runs on Mix start.boot; we inject SECRET_KEY_BASE via -eval).
  defp patch_bacview_script_for_android(_args) do
    path = Path.expand("src-tauri/target/rel/bin/bacview")

    if File.exists?(path) do
      content = File.read!(path)

      # Config.Provider (runtime.exs / SECRET_KEY_BASE) only runs on Mix start.boot.
      # Android uses start_clean, so we load runtime.exs via Config.Reader first.
      android_start = """
      start () {
        export_release_sys_config
        shift
        ERTS_VSN="$(cut -d' ' -f1 "$RELEASE_ROOT/releases/start_erl.data")"
        BINDIR="$RELEASE_ROOT/erts-$ERTS_VSN/bin"
        export ROOTDIR="$RELEASE_ROOT"
        export ERL_ROOTDIR="$RELEASE_ROOT"
        export RELEASE_ROOT
        export RELEASE_VSN
        export BINDIR
        export EMU=beam
        export PROGNAME=erl
        export PATH="$BINDIR:$PATH"
        if [ -z "$HOME" ]; then
          export HOME="$RELEASE_ROOT"
        fi
        BOOT="$RELEASE_ROOT/bin/start_clean"
        if [ ! -f "${BOOT}.boot" ] && [ ! -f "$BOOT" ]; then
          for b in "$RELEASE_ROOT"/releases/*/start_clean; do
            if [ -f "${b}.boot" ] || [ -f "$b" ]; then BOOT="$b"; break; fi
          done
        fi
        if [ -z "$SECRET_KEY_BASE" ]; then
          echo "ERROR: SECRET_KEY_BASE is not set" >&2
          exit 1
        fi
        exec "$BINDIR/erlexec" \\
          -boot "$BOOT" \\
          -boot_var ROOT "$RELEASE_ROOT" \\
          -config "$RELEASE_SYS_CONFIG" \\
          -pa "$REL_VSN_DIR/consolidated" \\
          -home "$HOME" \\
          -noshell \\
          -eval 'code:add_paths(filelib:wildcard("lib/*/ebin")),application:ensure_all_started(elixir),application:load(bacview),Secret=list_to_binary(os:getenv("SECRET_KEY_BASE")),Host=list_to_binary(case os:getenv("PHX_HOST") of false -> "127.0.0.1"; H -> H end),Port=list_to_integer(case os:getenv("PORT") of false -> "0"; P -> P end),Ep='"'"'Elixir.BacViewWeb.Endpoint'"'"',Curr=application:get_env(bacview, Ep, []),Curr1=lists:keystore(secret_key_base, 1, Curr, {secret_key_base, Secret}),Curr2=lists:keystore(server, 1, Curr1, {server, true}),Curr3=lists:keystore(url, 1, Curr2, {url, [{host, Host}, {port, Port}, {scheme, <<"http">>}]}),Http0=proplists:get_value(http, Curr3, []),Http1=lists:keystore(ip, 1, Http0, {ip, {127,0,0,1}}),Http2=lists:keystore(port, 1, Http1, {port, Port}),Curr4=lists:keystore(http, 1, Curr3, {http, Http2}),application:set_env(bacview, Ep, Curr4, [{persistent, true}]),application:ensure_all_started(bacview),receive after infinity -> ok end.'
      }
      """

      # Replace the existing start () { ... } function body (non-greedy via manual scan)
      patched =
        case Regex.run(~r/start \(\) \{\n.*?\n\}\n\nexport_release_sys_config/s, content) do
          [full] ->
            String.replace(content, full, android_start <> "\nexport_release_sys_config")

          _ ->
            # Fallback: only sh-wrap elixir execs
            content
            |> String.replace(
              ~s|exec "$REL_VSN_DIR/elixir"|,
              ~s|exec /system/bin/sh "$REL_VSN_DIR/elixir"|
            )
            |> String.replace(
              ~s|exec "$REL_VSN_DIR/$REL_EXEC"|,
              ~s|exec /system/bin/sh "$REL_VSN_DIR/$REL_EXEC"|
            )
        end

      File.write!(path, patched)
      IO.puts("patched bin/bacview start for Android (start_clean + ensure_all_started)")
    end
  end

  # Single zip is easier to pull out of APK assets on first Android launch.
  defp zip_release_for_android(_args) do
    rel = Path.expand("src-tauri/target/rel")
    zip_path = Path.expand("src-tauri/target/app-release.zip")

    if File.dir?(rel) do
      File.rm(zip_path)

      {_, 0} =
        System.cmd(
          "bash",
          ["-lc", "cd #{Path.expand("src-tauri/target")} && zip -qry app-release.zip rel"],
          into: IO.stream(:stdio, :line)
        )

      unless File.exists?(zip_path) do
        raise "failed to create #{zip_path}"
      end
    end
  end

  defp strip_gz_under(root) when is_binary(root) do
    if File.dir?(root) do
      root
      |> Path.join("**/*.gz")
      |> Path.wildcard()
      |> Enum.each(&File.rm/1)
    end
  end

  defp package() do
    [
      name: "BacView",
      name_long: "BacView BACnet Explorer",
      description: "BACnet explorer built in Elixir.",
      description_long:
        "Discover BACnet devices, browse objects, subscribe to COV updates, and monitor alarms.",
      icon: "priv/static/icon.png",
      category_gnome: "GNOME;GTK;Network;",
      identifier: "dev.bacview.app"
    ]
  end

  def desktop_mode?(), do: System.get_env("BACVIEW_DESKTOP") in ~w(1 true yes)

  defp include_circuits_uart?() do
    case System.get_env("BACVIEW_ENABLE_MSTP") do
      nil ->
        Code.ensure_loaded?(Circuits.UART) or not windows?()

      str ->
        str in ~w(1 true yes)
    end
  end

  defp windows?(), do: match?({:win32, _}, :os.type())
end
