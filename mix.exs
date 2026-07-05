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
      preferred_envs: [precommit: :test, desktop_installer: :prod, "desktop.installer": :prod]
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
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dns_cluster, "~> 0.2.0"},
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
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp desktop_deps() do
    if desktop_mode?() do
      [
        {:desktop, github: "elixir-desktop/desktop"},
        {:desktop_deployment, github: "elixir-desktop/deployment", runtime: false}
      ]
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
        "cmd BACVIEW_DESKTOP=1 mix deps.get",
        "assets.setup",
        "cmd BACVIEW_DESKTOP=1 mix compile"
      ],
      "desktop.server": ["cmd BACVIEW_DESKTOP=1 mix run --no-halt"],
      desktop_installer: [
        "assets.deploy",
        "cmd BACVIEW_DESKTOP=1 mix desktop.installer"
      ],
      precommit: [
        "deps.unlock --unused",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --all",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp releases() do
    web_release = [
      bacview: [
        include_executables_for: [:windows, :unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar],
        overlays: ["rel/overlays"]
      ]
    ]

    if desktop_mode?() do
      Keyword.put(web_release, :bacview_desktop,
        include_executables_for: [:windows, :unix],
        applications: [runtime_tools: :permanent, ssl: :permanent],
        steps: [:assemble, &Desktop.Deployment.generate_installer/1]
      )
    else
      web_release
    end
  end

  defp package() do
    [
      name: "BacView",
      name_long: "BacView BACnet Explorer",
      description: "BACnet network explorer for desktop",
      description_long:
        "Discover BACnet devices, browse objects, subscribe to COV updates, and monitor alarms.",
      icon: "priv/icon.png",
      category_gnome: "GNOME;GTK;Network;",
      identifier: "dev.bacview.app"
    ]
  end

  def desktop_mode?(), do: System.get_env("BACVIEW_DESKTOP") in ~w(1 true yes)

  defp include_circuits_uart?(), do: not windows?()

  defp windows?(), do: match?({:win32, _}, :os.type())
end
