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

    env_desktop =
      if windows?() do
        "set BACVIEW_DESKTOP=1&&"
      else
        "BACVIEW_DESKTOP=1"
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
        "cmd#{cmd_prefix} #{env_desktop} mix deps.get",
        "cmd#{cmd_prefix} #{env_desktop} mix deps.compile",
        "assets.setup",
        "cmd#{cmd_prefix} #{env_desktop} mix compile",
        "cmd#{cmd_prefix} cd src-tauri && cargo install tauri-cli --version \"^2.11.4\" --locked || true",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri icon ../priv/static/icon.png"
      ],
      "desktop.server": [
        "cmd#{cmd_prefix} #{env_desktop} mix compile --force",
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri dev"
      ],
      "desktop.prepare_release": [
        "desktop.setup",
        "assets.deploy",
        "compile --force",
        "release --overwrite --path src-tauri/target/rel"
      ],
      "desktop.installer": [
        "desktop.prepare_release",
        # "cmd#{cmd_prefix} cd src-tauri && cargo tauri build --bundles deb"
        "cmd#{cmd_prefix} cd src-tauri && cargo tauri build"
      ],
      # "mobile.prepare_release": [
      #   "desktop.setup",
      #   fn _args -> Enum.each(Path.wildcard("src-tauri/target/rel/**/*.gz"), &File.rm/1) end,
      #   "release --overwrite --path src-tauri/target/rel"
      # ],
      # "mobile.android_dev": [
      #   "mobile.prepare_release",
      #   "cmd#{cmd_prefix} cd src-tauri && cargo tauri android dev"
      # ],
      # "mobile.android.build": [
      #   "mobile.prepare_release",
      #   "cmd#{cmd_prefix} cd src-tauri && cargo tauri android build"
      # ],
      precommit: [
        "deps.unlock --unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --all",
        "dialyzer",
        "test --warnings-as-errors"
      ]
    ]
  end

  defp releases() do
    if desktop_mode?() do
      [
        bacview: [
          include_executables_for: [:windows, :unix],
          applications: [runtime_tools: :permanent, ssl: :permanent],
          # codesign is for MacOS - see elixirkit!
          # &ElixirKit.Release.codesign/1
          steps: [:assemble]
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
