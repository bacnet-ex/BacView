defmodule BacViewWeb.HierarchyNodeIcon do
  @moduledoc false

  @node_type_icons %{
    system: "hero-server-stack",
    network: "hero-globe-alt",
    device: "hero-cpu-chip",
    organizational: "hero-building-office",
    area: "hero-map",
    equipment: "hero-wrench-screwdriver",
    point: "hero-map-pin",
    collection: "hero-folder-open",
    property: "hero-adjustments-horizontal",
    functional: "hero-command-line",
    other: "hero-question-mark-circle",
    subsystem: "hero-puzzle-piece",
    building: "hero-building-office-2",
    floor: "hero-bars-3-bottom-left",
    section: "hero-rectangle-stack",
    module: "hero-cube",
    tree: "hero-share",
    member: "hero-link",
    protocol: "hero-signal",
    room: "hero-home-modern",
    zone: "hero-view-columns",
    unknown: "hero-folder"
  }

  @spatial ~w(building floor room area zone section)a
  @equipment ~w(system subsystem equipment device module)a
  @logical ~w(organizational network collection tree functional point member property protocol other)a

  @fallback_icon "hero-folder"
  @fallback_color "text-[var(--bac-amber)]"

  @spec name(atom() | nil) :: String.t()
  def name(nil), do: @fallback_icon

  def name(node_type) when is_atom(node_type),
    do: Map.get(@node_type_icons, node_type, @fallback_icon)

  @spec color_class(atom() | nil) :: String.t()
  def color_class(nil), do: @fallback_color

  def color_class(node_type) when is_atom(node_type) do
    cond do
      node_type in @spatial -> "text-[var(--bac-amber)]"
      node_type in @equipment -> "text-[var(--bac-accent)]"
      node_type in @logical -> "text-[var(--bac-text-muted)]"
      node_type == :unknown -> @fallback_color
      true -> @fallback_color
    end
  end

  @spec icon_class(atom() | nil, String.t()) :: String.t()
  def icon_class(node_type, size_class \\ "size-4") do
    "#{size_class} shrink-0 #{color_class(node_type)}"
  end

  @spec tooltip(String.t() | nil) :: String.t() | nil
  def tooltip(nil), do: nil

  def tooltip(subtype) when is_binary(subtype) do
    case String.trim(subtype) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc false
  @spec names() :: [String.t()]
  # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
  def names(), do: Map.values(@node_type_icons) ++ [@fallback_icon]
end
