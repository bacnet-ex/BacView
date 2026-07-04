defmodule BacViewWeb.LiveFlash do
  @moduledoc false

  import Phoenix.LiveView

  alias BacView.BACnet.Protocol.ErrorMessage

  @doc """
  Shows a user-friendly error toast and logs the full reason to the browser
  console via a LiveView push event.
  """
  @spec put_error(Phoenix.LiveView.Socket.t(), ErrorMessage.action(), term()) ::
          Phoenix.LiveView.Socket.t()
  def put_error(socket, action, reason) do
    message = ErrorMessage.for_action(action, reason)
    detail = ErrorMessage.detail(reason)

    socket
    |> push_event("log_error", %{
      "action" => Atom.to_string(action),
      "message" => message,
      "detail" => detail
    })
    |> put_flash(:error, message)
  end
end
