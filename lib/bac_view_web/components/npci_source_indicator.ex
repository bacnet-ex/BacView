defmodule BacViewWeb.NpciSourceIndicator do
  @moduledoc false
  use BacViewWeb, :html
  use BacViewWeb.LocaleAttrs

  alias BACnet.Protocol.NpciTarget
  alias BacView.BACnet.Address

  attr(:npci_source, :any, default: nil)
  attr(:id, :string, default: nil)
  attr(:class, :string, default: nil)

  def npci_source_indicator(assigns) do
    assigns =
      assign(
        assigns,
        :label,
        tooltip_label(assigns.npci_source, assigns.locale, assigns.locale_version)
      )

    ~H"""
    <span
      :if={@label}
      id={@id}
      class={["inline-flex items-center shrink-0 text-[var(--bac-text-faint)]", @class]}
      title={@label}
      aria-label={@label}
    >
      <.icon name="hero-globe-alt" class="size-3.5" />
    </span>
    """
  end

  defp tooltip_label(%NpciTarget{} = source, locale, locale_version) do
    t(locale, locale_version, "NPCI-Quelle: %{target}",
      target: Address.format_npci_target(source)
    )
  end

  defp tooltip_label(_source, _locale, _locale_version), do: nil
end
