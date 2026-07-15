defmodule BacViewWeb.PropertyValue do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BacView.BACnet.Protocol.PropertyDisplay

  attr(:display, :map, required: true)
  attr(:writable, :boolean, default: false)
  attr(:property, :any, default: nil)
  attr(:writing, :boolean, default: false)
  attr(:collapse_nested, :boolean, default: false)
  attr(:dom_id_prefix, :string, default: "row")

  def property_value(assigns) do
    ~H"""
    <div class="bac-property-value min-w-0">
      <%= case @display.kind do %>
        <% :struct -> %>
          <%= if collapsible?(@display, @writable) do %>
            <.collapsible_block
              id={collapsible_id(@dom_id_prefix, @property, "struct")}
              summary={PropertyDisplay.brief_summary(@display)}
              locale={@locale}
              locale_version={@locale_version}
            >
              <.struct_fields
                fields={@display.fields}
                writable={@writable}
                property={@property}
                writing={@writing}
                collapse_nested={true}
                dom_id_prefix={@dom_id_prefix}
                locale={@locale}
                locale_version={@locale_version}
              />
            </.collapsible_block>
          <% else %>
            <.struct_fields
              fields={@display.fields}
              writable={@writable}
              property={@property}
              writing={@writing}
              collapse_nested={@collapse_nested}
              dom_id_prefix={@dom_id_prefix}
              locale={@locale}
              locale_version={@locale_version}
            />
          <% end %>
        <% :priority_array -> %>
          <.collapsible_block
            id={collapsible_id(@dom_id_prefix, @property, "priority-array")}
            summary={PropertyDisplay.brief_summary(@display)}
            locale={@locale}
            locale_version={@locale_version}
          >
            <.priority_array_items items={@display.items} />
          </.collapsible_block>
        <% kind when kind in [:array, :list] -> %>
          <.collapsible_block
            id={collapsible_id(@dom_id_prefix, @property, Atom.to_string(kind))}
            summary={
              t(@locale, @locale_version, "%{count} Einträge",
                count: length(@display.items)
              )
            }
            locale={@locale}
            locale_version={@locale_version}
          >
            <div class="bac-array-items space-y-1.5">
              <.array_item
                :for={item <- @display.items}
                item={item}
                property={@property}
                writing={@writing}
                dom_id_prefix={@dom_id_prefix}
                locale={@locale}
                locale_version={@locale_version}
              />
            </div>
          </.collapsible_block>
        <% kind when kind in [:object_identifier, :scalar] -> %>
          <%= if collapsible?(@display, @writable) do %>
            <.collapsible_block
              id={collapsible_id(@dom_id_prefix, @property, "value")}
              summary={collapse_summary(@display)}
              locale={@locale}
              locale_version={@locale_version}
            >
              <span class="bac-mono text-sm text-[var(--bac-text)] break-all">{@display.formatted}</span>
            </.collapsible_block>
          <% else %>
            <span class="bac-mono text-[var(--bac-text)]">{@display.formatted}</span>
          <% end %>
      <% end %>
    </div>
    """
  end

  attr(:fields, :list, required: true)
  attr(:writable, :boolean, default: false)
  attr(:property, :any, default: nil)
  attr(:writing, :boolean, default: false)
  attr(:collapse_nested, :boolean, default: false)
  attr(:dom_id_prefix, :string, default: "row")
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp struct_fields(assigns) do
    ~H"""
    <div class="bac-struct-fields">
      <.struct_field
        :for={field <- @fields}
        field={field}
        depth={0}
        writable={@writable}
        property={@property}
        writing={@writing}
        collapse_nested={@collapse_nested}
        dom_id_prefix={@dom_id_prefix}
        locale={@locale}
        locale_version={@locale_version}
      />
    </div>
    """
  end

  attr(:items, :list, required: true)

  defp priority_array_items(assigns) do
    ~H"""
    <div class="bac-priority-array">
      <div :for={slot <- @items} class="bac-priority-row flex items-center gap-3 py-1">
        <span class="bac-mono text-xs bac-text-faint w-8 shrink-0">{slot.label}</span>
        <span class="bac-mono text-sm text-[var(--bac-text)]">{slot.formatted}</span>
      </div>
    </div>
    """
  end

  attr(:item, :map, required: true)
  attr(:property, :any, default: nil)
  attr(:writing, :boolean, default: false)
  attr(:dom_id_prefix, :string, default: "row")
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp array_item(assigns) do
    display = array_item_display(assigns.item)

    assigns =
      assigns
      |> assign(:display, display)
      |> assign(:nested?, nested_display?(display))

    ~H"""
    <%= if @nested? do %>
      <.collapsible_block
        id={collapsible_id(@dom_id_prefix, @property, "array-item", @item.key)}
        summary={"#{@item.label} #{PropertyDisplay.brief_summary(@display)}"}
        locale={@locale}
        locale_version={@locale_version}
        class="bac-array-item"
      >
        <.property_value
          display={@display}
          writable={false}
          property={@property}
          writing={@writing}
          collapse_nested={true}
          dom_id_prefix={@dom_id_prefix}
          locale={@locale}
          locale_version={@locale_version}
        />
      </.collapsible_block>
    <% else %>
      <div class="bac-array-item flex flex-wrap items-baseline gap-2 py-0.5 pl-3 border-l border-[var(--bac-border)]">
        <span class="text-xs bac-text-faint">{@item.label}</span>
        <span class="bac-mono text-sm text-[var(--bac-text)]">{@display.formatted}</span>
      </div>
    <% end %>
    """
  end

  attr(:id, :string, required: true)
  attr(:summary, :string, required: true)
  attr(:class, :string, default: "")
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)
  slot(:inner_block, required: true)

  defp collapsible_block(assigns) do
    ~H"""
    <details id={@id} class={["bac-collapsible min-w-0", @class]}>
      <summary class="bac-collapsible-summary min-w-0">
        <.icon name="hero-chevron-right" class="bac-collapsible-icon size-3.5 shrink-0" />
        <span class="bac-mono text-sm text-[var(--bac-text)] truncate">{@summary}</span>
      </summary>
      <div class="bac-collapsible-content min-w-0">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr(:field, :map, required: true)
  attr(:depth, :integer, default: 0)
  attr(:writable, :boolean, default: false)
  attr(:property, :any, default: nil)
  attr(:writing, :boolean, default: false)
  attr(:collapse_nested, :boolean, default: false)
  attr(:dom_id_prefix, :string, default: "row")
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  defp struct_field(assigns) do
    ~H"""
    <div class={["bac-struct-field", @depth > 0 && "ml-3 pl-3 border-l border-[var(--bac-border)]"]}>
      <%= cond do %>
        <% @field.kind == :boolean -> %>
          <input
            :if={@writable}
            type="hidden"
            name={struct_field_name(@property, @field.key)}
            value="false"
          />
          <label class="flex items-center gap-2 py-1">
            <input
              type="checkbox"
              checked={@field.value == true}
              disabled={!@writable}
              name={if(@writable, do: struct_field_name(@property, @field.key))}
              value="true"
              class="bac-checkbox"
            />
            <span class="text-sm text-[var(--bac-text)]">{@field.label}</span>
          </label>
        <% @collapse_nested && nested_field?(@field) -> %>
          <.collapsible_block
            id={collapsible_id(@dom_id_prefix, @property, "field", @field.key)}
            summary={"#{@field.label}: #{PropertyDisplay.brief_summary(field_display(@field))}"}
            locale={@locale}
            locale_version={@locale_version}
            class="py-0.5"
          >
            <.property_value
              display={field_display(@field)}
              writable={false}
              property={@property}
              writing={@writing}
              collapse_nested={false}
              dom_id_prefix={@dom_id_prefix}
              locale={@locale}
              locale_version={@locale_version}
            />
          </.collapsible_block>
        <% @field.kind == :struct and @field.fields != [] -> %>
          <p class="text-xs font-medium text-[var(--bac-text-muted)] py-1">{@field.label}</p>
          <.struct_field
            :for={nested <- @field.fields}
            field={nested}
            depth={@depth + 1}
            writable={false}
            property={@property}
            writing={@writing}
            collapse_nested={@collapse_nested}
            dom_id_prefix={@dom_id_prefix}
            locale={@locale}
            locale_version={@locale_version}
          />
        <% @field.kind == :priority_array and match?(%{items: items} when is_list(items), @field) -> %>
          <p class="text-xs font-medium text-[var(--bac-text-muted)] py-1">{@field.label}</p>
          <div class="bac-priority-array ml-3">
            <div :for={slot <- @field.items} class="bac-priority-row flex items-center gap-3 py-0.5">
              <span class="bac-mono text-xs bac-text-faint w-8">{slot.label}</span>
              <span class="bac-mono text-sm">{slot.formatted}</span>
            </div>
          </div>
        <% @field.kind in [:array, :list] and match?(%{items: items} when is_list(items), @field) -> %>
          <.collapsible_block
            id={collapsible_id(@dom_id_prefix, @property, "field-#{@field.kind}", @field.key)}
            summary={"#{@field.label}: #{PropertyDisplay.brief_summary(field_display(@field))}"}
            locale={@locale}
            locale_version={@locale_version}
            class="py-0.5"
          >
            <div class="bac-array-items space-y-1.5">
              <.array_item
                :for={item <- @field.items}
                item={item}
                property={@property}
                writing={@writing}
                dom_id_prefix={@dom_id_prefix}
                locale={@locale}
                locale_version={@locale_version}
              />
            </div>
          </.collapsible_block>
        <% true -> %>
          <div class="flex flex-wrap items-baseline gap-2 py-1">
            <span class="text-sm text-[var(--bac-text-muted)]">{@field.label}</span>
            <span class="bac-mono text-sm text-[var(--bac-text)]">{@field.formatted}</span>
          </div>
      <% end %>
    </div>
    """
  end

  defp array_item_display(%{kind: kind, formatted: formatted, fields: fields, items: items})
       when kind in [:struct, :priority_array, :array, :list] do
    %{kind: kind, formatted: formatted, fields: fields || [], items: items || []}
  end

  defp array_item_display(%{fields: fields, formatted: formatted, items: items})
       when is_list(fields) and fields != [] do
    %{kind: :struct, formatted: formatted, fields: fields, items: items || []}
  end

  defp array_item_display(%{items: items, formatted: formatted})
       when is_list(items) and items != [] do
    %{kind: :array, formatted: formatted, fields: [], items: items}
  end

  defp array_item_display(%{formatted: formatted}) do
    %{kind: :scalar, formatted: formatted, fields: [], items: []}
  end

  defp field_display(%{kind: kind, formatted: formatted, fields: fields, items: items})
       when kind in [:struct, :priority_array, :array, :list] do
    %{kind: kind, formatted: formatted, fields: fields || [], items: items || []}
  end

  defp field_display(%{formatted: formatted}) do
    %{kind: :scalar, formatted: formatted, fields: [], items: []}
  end

  defp nested_display?(%{kind: :struct, fields: fields}) when fields != [], do: true

  defp nested_display?(%{kind: kind, items: items})
       when kind in [:array, :list] and items != [],
       do: true

  defp nested_display?(%{kind: :priority_array, items: items}) when items != [], do: true
  defp nested_display?(_nested_display), do: false

  defp nested_field?(%{kind: kind}) when kind in [:struct, :array, :list, :priority_array],
    do: true

  defp nested_field?(_nested_field), do: false

  defp collapsible_id(dom_id_prefix, property, suffix, key \\ nil) do
    base =
      property
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")

    parts = Enum.reject([dom_id_prefix, base, suffix, key], &is_nil/1)
    "bac-collapsible-" <> Enum.join(parts, "-")
  end

  defp struct_field_name(property, key) when is_atom(property) and is_atom(key) do
    "#{property}_#{key}"
  end

  defp struct_field_name(property, key), do: "#{property}_#{key}"

  @collapse_char_limit 60

  defp collapsible?(%{kind: :struct, fields: fields}, writable) when fields != [] do
    not writable
  end

  defp collapsible?(%{kind: kind}, _writable) when kind in [:array, :list, :priority_array],
    do: true

  defp collapsible?(%{kind: kind, formatted: formatted}, _writable)
       when kind in [:scalar, :object_identifier] and is_binary(formatted) do
    String.length(formatted) > @collapse_char_limit
  end

  defp collapsible?(_assigns, _collapsible2), do: false

  defp collapse_summary(%{formatted: formatted}) when is_binary(formatted) do
    if String.length(formatted) > @collapse_char_limit do
      String.slice(formatted, 0, @collapse_char_limit) <> "…"
    else
      formatted
    end
  end

  defp collapse_summary(display), do: PropertyDisplay.brief_summary(display)
end
