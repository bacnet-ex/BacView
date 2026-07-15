defmodule BacViewWeb.ErrorMessageText do
  @moduledoc false

  alias BacView.BACnet.Protocol.ErrorMessage

  @spec format(term(), String.t() | nil, integer()) :: String.t()
  def format(reason, locale, locale_version) do
    _track = locale_version
    locale = locale || Gettext.get_locale(BacViewWeb.Gettext) || "de"

    Gettext.with_locale(BacViewWeb.Gettext, locale, fn ->
      ErrorMessage.format_reason(reason)
    end)
  end
end
