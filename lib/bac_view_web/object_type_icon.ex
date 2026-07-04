defmodule BacViewWeb.ObjectTypeIcon do
  @moduledoc false

  @object_type_icons %{
    analog_input: "hero-signal",
    analog_output: "hero-arrow-trending-up",
    analog_value: "hero-variable",
    binary_input: "hero-bolt",
    binary_output: "hero-power",
    binary_value: "hero-arrows-right-left",
    device: "hero-cpu-chip",
    structured_view: "hero-folder",
    trend_log: "hero-presentation-chart-line",
    trend_log_multiple: "hero-presentation-chart-bar",
    file: "hero-document"
  }

  @fallback "hero-cube"

  @spec name(atom() | String.t() | nil) :: String.t()
  def name(type) when is_atom(type), do: Map.get(@object_type_icons, type, @fallback)

  def name(type) when is_binary(type) do
    type |> String.to_existing_atom() |> name()
  rescue
    ArgumentError -> @fallback
  end

  def name(_object_type_icons), do: @fallback

  @doc false
  @spec names() :: [String.t()]
  # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
  def names(), do: Map.values(@object_type_icons) ++ [@fallback]
end
