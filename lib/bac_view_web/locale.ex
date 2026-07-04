defmodule BacViewWeb.Locale do
  @moduledoc false

  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias BacViewWeb.LocaleRefresh
  alias BacViewWeb.LocaleStore

  @spec set_locale(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def set_locale(socket, locale) when locale in ["de", "en"] do
    Gettext.put_locale(BacViewWeb.Gettext, locale)

    if connected?(socket) do
      LocaleStore.put(Phoenix.LiveView.transport_pid(socket), locale)
    end

    socket
    |> Phoenix.Component.assign(:locale, locale)
    |> LocaleRefresh.refresh_socket()
    |> push_event("persist_locale", %{locale: locale})
  end
end
