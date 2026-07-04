defmodule BacViewWeb.LiveFlashTest do
  use BacViewWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BACnet.Protocol.APDU
  alias BacViewWeb.LiveFlash

  defmodule FlashLive do
    use BacViewWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      {:ok, LiveFlash.put_error(socket, :cov_subscribe, {:bacnet_error, sample_error()})}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <Layouts.app flash={@flash} locale="de" locale_version={0}>
        <div id="flash-live-test">ok</div>
      </Layouts.app>
      """
    end

    defp sample_error do
      %APDU.Error{
        invoke_id: 1,
        service: :subscribe_cov_property,
        class: :services,
        code: :not_cov_property,
        payload: []
      }
    end
  end

  setup do
    {:ok, view, _html} = live_isolated(build_conn(), FlashLive, [])
    {:ok, view: view}
  end

  test "puts user-friendly flash and pushes console log event", %{view: view} do
    assert render(view) =~ "COV-Abonnement fehlgeschlagen"
    assert render(view) =~ "COV-Benachrichtigungen"
    refute render(view) =~ "invoke_id"

    assert_push_event(view, "log_error", %{
      "action" => "cov_subscribe",
      "message" => message,
      "detail" => detail
    })

    assert message =~ "COV-Abonnement fehlgeschlagen"
    assert detail =~ "not_cov_property"
  end
end
