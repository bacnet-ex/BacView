defmodule BacViewWeb.LocaleHook do
  @moduledoc """
  Sets the Gettext locale from the LiveView session on mount.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias BacViewWeb.Locale
  alias BacViewWeb.LocaleStore

  def on_mount(:default, _params, session, socket) do
    locale =
      transport_locale(socket) ||
        get_connect_params(socket)["locale"] ||
        session["locale"] ||
        Application.get_env(:bacview, BacViewWeb.Gettext)[:default_locale] ||
        "de"

    Gettext.put_locale(BacViewWeb.Gettext, locale)

    {:cont,
     socket
     |> assign(:locale, locale)
     |> assign(:locale_version, 0)
     |> attach_hook(:locale, :handle_params, &handle_params/3)
     |> attach_hook(:locale_event, :handle_event, &handle_locale_event/3)
     |> attach_hook(:locale_process, :handle_event, &ensure_locale/3)}
  end

  defp handle_locale_event("set_locale", %{"locale" => locale}, socket) do
    {:halt, Locale.set_locale(socket, locale)}
  end

  defp handle_locale_event(_event, _params, socket), do: {:cont, socket}

  defp ensure_locale(_event, _params, socket) do
    Gettext.put_locale(BacViewWeb.Gettext, socket.assigns.locale)
    {:cont, socket}
  end

  defp handle_params(_params, _uri, socket) do
    Gettext.put_locale(BacViewWeb.Gettext, socket.assigns.locale)
    {:cont, socket}
  end

  defp transport_locale(socket) do
    if connected?(socket) do
      LocaleStore.get(transport_pid(socket))
    end
  end
end
