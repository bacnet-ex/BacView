defmodule Mix.Tasks.Bacview.Desktop.Check do
  @shortdoc "Verifies desktop build prerequisites when BACVIEW_DESKTOP=1"
  @moduledoc false

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    if System.get_env("BACVIEW_DESKTOP") in ~w(1 true yes) do
      unless Code.ensure_loaded?(Desktop) do
        Mix.raise("""
        BACVIEW_DESKTOP=1 is set but the :desktop dependency is missing.

        Run:

            BACVIEW_DESKTOP=1 mix deps.get
            BACVIEW_DESKTOP=1 mix compile
        """)
      end

      Mix.shell().info("Desktop mode: :desktop dependency present.")
    else
      Mix.shell().info("Web mode: BACVIEW_DESKTOP is not set.")
    end
  end
end
