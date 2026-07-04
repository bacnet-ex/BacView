defmodule BacViewWeb.SortHeader do
  @moduledoc false
  use BacViewWeb, :html

  attr(:event, :string, required: true)
  attr(:column, :string, required: true)
  attr(:label, :string, required: true)
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :atom, default: :asc)
  attr(:id_prefix, :string, default: "sort")

  def sort_header(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@id_prefix}-#{@column}"}
      phx-click={@event}
      phx-value-column={@column}
      class={[
        "bac-sort-header",
        @sort_by == @column && "bac-sort-header-active"
      ]}
      aria-sort={if @sort_by == @column, do: Atom.to_string(@sort_dir), else: "none"}
    >
      <span>{@label}</span>
      <.icon
        :if={@sort_by == @column && @sort_dir == :asc}
        name="hero-chevron-up"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by == @column && @sort_dir == :desc}
        name="hero-chevron-down"
        class="size-3.5"
      />
      <.icon
        :if={@sort_by != @column}
        name="hero-chevron-up-down"
        class="size-3.5 opacity-35"
      />
    </button>
    """
  end
end
