defmodule BacViewWeb.SCCredentialsLive do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, to_form: 1]

  import Phoenix.LiveView,
    only: [allow_upload: 3, consume_uploaded_entries: 3, uploaded_entries: 2]

  alias BacView.BACnet.SCCredentials
  alias BacViewWeb.SCPemUploadWriter

  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket) do
    summary =
      case SCCredentials.summary() do
        {:ok, summary} -> summary
        {:error, _reason} -> nil
      end

    socket
    |> assign(sc_credentials: summary, sc_credentials_form: to_form(%{}), sc_import_result: nil)
    |> allow_upload(:sc_certificate, upload_opts(1))
    |> allow_upload(:sc_key, upload_opts(1))
    |> allow_upload(:sc_issuers, upload_opts(2))
  end

  @spec import_credentials(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def import_credentials(socket) do
    if ready_to_import?(socket) do
      [cert] = consume(socket, :sc_certificate)
      [key] = consume(socket, :sc_key)
      issuers = consume(socket, :sc_issuers)

      case SCCredentials.import_pem(cert, key, issuers) do
        {:ok, summary} -> assign(socket, sc_credentials: summary, sc_import_result: :imported)
        {:error, reason} -> assign(socket, sc_import_result: reason)
      end
    else
      assign(socket, sc_import_result: :missing_sc_credentials)
    end
  end

  defp ready_to_import?(socket) do
    match?({[_entry], []}, uploaded_entries(socket, :sc_certificate)) and
      match?({[_entry], []}, uploaded_entries(socket, :sc_key)) and
      match?({[_entry | _rest], []}, uploaded_entries(socket, :sc_issuers))
  end

  defp consume(socket, name) do
    consume_uploaded_entries(socket, name, fn %{pem: pem}, _entry -> {:ok, pem} end)
  end

  defp upload_opts(max_entries) do
    [
      accept: :any,
      max_entries: max_entries,
      max_file_size: SCCredentials.max_pem_size(),
      writer: fn _name, _entry, _socket -> {SCPemUploadWriter, []} end
    ]
  end
end
