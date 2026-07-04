defmodule BacView.BACnet.FileTransfer do
  @moduledoc """
  Chunked Atomic Read/Write File transfers for BACnet File objects.
  """

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.Client

  @default_chunk_size 512
  @max_chunk_size 1024
  @preview_byte_limit 65_536

  @type read_result :: %{
          data: binary(),
          stream_access: boolean(),
          size: non_neg_integer()
        }

  @spec read_file(term(), ObjectIdentifier.t(), keyword()) ::
          {:ok, read_result()} | {:error, term()}
  def read_file(destination, %ObjectIdentifier{} = object, opts \\ []) do
    stream_access = Keyword.get(opts, :stream_access, true)

    chunk_size =
      if stream_access do
        min(Keyword.get(opts, :chunk_size, @default_chunk_size), @max_chunk_size)
      else
        Keyword.get(opts, :record_count, 1)
      end

    do_read(destination, object, stream_access, 0, chunk_size, <<>>)
  end

  @spec write_file(term(), ObjectIdentifier.t(), binary(), keyword()) ::
          :ok | {:error, term()}
  def write_file(destination, %ObjectIdentifier{} = object, data, opts \\ [])
      when is_binary(data) do
    stream_access = Keyword.get(opts, :stream_access, true)
    chunk_size = min(Keyword.get(opts, :chunk_size, @default_chunk_size), @max_chunk_size)
    start_position = Keyword.get(opts, :start_position, 0)

    do_write(destination, object, stream_access, start_position, data, chunk_size)
  end

  defp do_read(destination, object, stream_access, position, chunk_size, acc) do
    case Client.atomic_read_file(destination, object, stream_access, position, chunk_size) do
      {:ok, %{eof: true, data: data}} ->
        chunk = append_data(data, stream_access)
        result = acc <> chunk
        {:ok, %{data: result, stream_access: stream_access, size: byte_size(result)}}

      {:ok, %{eof: false, data: data} = ack} ->
        chunk = append_data(data, stream_access)
        next = next_read_position(stream_access, ack, chunk)
        do_read(destination, object, stream_access, next, chunk_size, acc <> chunk)

      {:error, _destination} = err ->
        err
    end
  end

  defp do_write(_destination, _object, _stream_access, _position, <<>>, _chunk_size), do: :ok

  defp do_write(destination, object, true = stream_access, position, data, chunk_size) do
    if byte_size(data) <= chunk_size do
      write_stream_chunk(destination, object, stream_access, position, data, <<>>, chunk_size)
    else
      <<chunk::binary-size(chunk_size), rest::binary>> = data
      write_stream_chunk(destination, object, stream_access, position, chunk, rest, chunk_size)
    end
  end

  defp do_write(destination, object, false = stream_access, position, data, chunk_size) do
    records = chunk_records(data, chunk_size)

    case Client.atomic_write_file(destination, object, stream_access, position, records) do
      {:ok, %{start_position: next}} ->
        written = Enum.reduce(records, 0, fn r, n -> n + byte_size(r) end)
        rest_size = byte_size(data) - written

        if rest_size <= 0 do
          :ok
        else
          remaining = binary_part(data, written, rest_size)
          do_write(destination, object, stream_access, next, remaining, chunk_size)
        end

      {:error, _destination} = err ->
        err
    end
  end

  defp write_stream_chunk(destination, object, stream_access, position, chunk, rest, chunk_size) do
    case Client.atomic_write_file(destination, object, stream_access, position, chunk) do
      {:ok, %{start_position: next}} ->
        if rest == <<>> do
          :ok
        else
          do_write(destination, object, stream_access, next + byte_size(chunk), rest, chunk_size)
        end

      {:error, _destination} = err ->
        err
    end
  end

  defp append_data(data, true) when is_binary(data), do: data

  defp append_data(records, false) when is_list(records) do
    Enum.reduce(records, <<>>, fn record, acc -> acc <> record end)
  end

  defp append_data(data, _data), do: to_string(data)

  defp next_read_position(true, %{start_position: start_pos}, chunk),
    do: start_pos + byte_size(chunk)

  defp next_read_position(false, %{start_position: start_pos, record_count: count}, _chunk)
       when is_integer(count) and count > 0,
       do: start_pos + count

  defp next_read_position(false, %{start_position: start_pos}, _chunk), do: start_pos + 1

  defp chunk_records(data, chunk_size) do
    data
    |> chunk_binary(chunk_size)
    |> Enum.to_list()
  end

  defp chunk_binary(data, size) do
    Stream.unfold(data, fn
      <<>> -> nil
      bin when byte_size(bin) <= size -> {bin, <<>>}
      <<chunk::binary-size(size), rest::binary>> -> {chunk, rest}
    end)
  end

  @doc "Extracts file metadata from property rows."
  @spec file_metadata([map()]) :: %{
          stream_access: boolean(),
          file_size: non_neg_integer() | nil,
          read_only: boolean()
        }
  def file_metadata(properties) when is_list(properties) do
    access = property_value(properties, :file_access_method)
    stream_access = access != :record_access

    %{
      stream_access: stream_access,
      file_size: property_value(properties, :file_size),
      read_only: property_value(properties, :read_only) == true
    }
  end

  defp property_value(properties, key) do
    case Enum.find(properties, &(&1.property == key)) do
      %{value: value} -> value
      _properties -> nil
    end
  end

  @doc "Suggested download filename for a file object."
  @spec filename(atom(), non_neg_integer()) :: String.t()
  def filename(type, instance) do
    "bacview-#{type}-#{instance}.bin"
  end

  @doc """
  Builds a UI-friendly view of file bytes for preview and download.
  """
  @spec content_view(binary()) :: %{
          printable: boolean(),
          preview: String.t() | nil,
          truncated: boolean(),
          size: non_neg_integer()
        }
  def content_view(data) when is_binary(data) do
    printable = printable_text?(data)
    truncated = byte_size(data) > @preview_byte_limit

    preview =
      if printable do
        if truncated, do: binary_part(data, 0, @preview_byte_limit), else: data
      else
        nil
      end

    %{
      printable: printable,
      preview: preview,
      truncated: truncated,
      size: byte_size(data)
    }
  end

  @doc "Returns true when file bytes are safe to show as text in the browser."
  @spec printable_text?(binary()) :: boolean()
  def printable_text?(<<>>), do: true

  def printable_text?(data) when is_binary(data) do
    String.valid?(data) and :binary.match(data, <<0>>) == :nomatch and String.printable?(data)
  end

  @doc "MIME type for downloaded file content."
  @spec content_mime(boolean()) :: String.t()
  def content_mime(true), do: "text/plain;charset=utf-8"
  def content_mime(false), do: "application/octet-stream"

  @doc "Download filename adjusted for printable text files."
  @spec download_filename(atom(), non_neg_integer(), boolean()) :: String.t()
  def download_filename(type, instance, printable?) do
    ext = if printable?, do: "txt", else: "bin"
    "bacview-#{type}-#{instance}.#{ext}"
  end
end
