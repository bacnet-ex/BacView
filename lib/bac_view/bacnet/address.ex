defmodule BacView.BACnet.Address do
  @moduledoc """
  Parses BACnet/IP host and port values and formats transport-layer destination
  addresses for display and comparison.
  """

  alias BACnet.Protocol.NpciTarget

  @bacnet_port 47_808
  @ipv4_port_range 47_808..65_535
  @max_scan_targets 256
  @octet_range_re ~r/^\[(\d+)-(\d+)\]$/

  @spec parse_host(String.t()) :: {:ok, :inet.ip_address()} | {:error, :invalid_host}
  def parse_host(host) when is_binary(host) do
    host = String.trim(host)

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, addr} -> {:ok, addr}
      {:error, _host} -> {:error, :invalid_host}
    end
  end

  def parse_host(_host), do: {:error, :invalid_host}

  @doc """
  Expands a scan target into one or more IPv4 addresses.

  Plain hosts (`192.168.1.10`) return a single address. Octet ranges use bracket
  notation (`192.168.100.[31-35]`). Multiple bracketed octets expand to the full
  cartesian product, up to #{@max_scan_targets} addresses.
  """
  @spec expand_scan_targets(String.t()) ::
          {:ok, [:inet.ip_address()]}
          | {:error, :invalid_host | {:too_many_targets, pos_integer()}}
  def expand_scan_targets(host) when is_binary(host) do
    host = String.trim(host)

    cond do
      host == "" ->
        {:error, :invalid_host}

      not String.contains?(host, "[") ->
        case parse_host(host) do
          {:ok, ip} -> {:ok, [ip]}
          {:error, _host} = err -> err
        end

      true ->
        expand_host_ranges(host)
    end
  end

  def expand_scan_targets(_host), do: {:error, :invalid_host}

  @spec parse_port(term()) :: {:ok, 1..65_535} | {:error, :invalid_port}
  def parse_port(port) when is_integer(port) and port in 1..65_535, do: {:ok, port}

  def parse_port(port) when is_binary(port) do
    case Integer.parse(String.trim(port)) do
      {int, ""} when int in 1..65_535 -> {:ok, int}
      _port -> {:error, :invalid_port}
    end
  end

  def parse_port(_port), do: {:error, :invalid_port}

  @spec format_ip(:inet.ip_address()) :: String.t()
  def format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  def format_ip(ip) when is_tuple(ip), do: ip |> Tuple.to_list() |> Enum.join(".")

  @doc """
  Normalizes a BACnet destination address from the active transport layer.

  IPv4 uses `{ip_tuple, port}`, MS/TP uses a MAC address integer (`0..255`), and
  unknown shapes are returned unchanged.
  """
  @spec normalize_destination(term()) :: term()
  def normalize_destination({ip, port}) when is_tuple(ip) and is_integer(port), do: {ip, port}

  def normalize_destination({ip, port, _tag}) when is_tuple(ip) and is_integer(port),
    do: {ip, port}

  def normalize_destination(mac) when is_integer(mac) and mac in 0..255, do: mac
  def normalize_destination(other), do: other

  @spec same_destination?(term(), term()) :: boolean()
  def same_destination?(left, right),
    do: normalize_destination(left) == normalize_destination(right)

  @doc "Formats any BACnet destination address for display."
  @spec format_destination(term()) :: String.t()
  def format_destination({ip, port}) when is_tuple(ip) and is_integer(port),
    do: "#{format_ip(ip)}:#{port}"

  def format_destination(mac) when is_integer(mac) and mac in 0..255, do: Integer.to_string(mac)
  def format_destination(other), do: inspect(other)

  @doc "Formats an NPCI source or destination target for display."
  @spec format_npci_target(NpciTarget.t() | nil) :: String.t()
  def format_npci_target(nil), do: "none"

  def format_npci_target(%NpciTarget{net: net, address: nil}), do: "#{net}/broadcast"

  def format_npci_target(%NpciTarget{net: net, address: address}) when is_integer(address) do
    "#{net}/#{format_npci_address(address)}"
  end

  defp format_npci_address(address) when address in 0..255, do: Integer.to_string(address)

  defp format_npci_address(address) when is_integer(address) and address >= 0 do
    binary = npci_address_to_binary(address)

    case byte_size(binary) do
      6 ->
        <<a, b, c, d, port_hi, port_lo>> = binary
        port = port_hi * 256 + port_lo

        if port in 1..65_535 do
          "#{a}.#{b}.#{c}.#{d}:#{port}"
        else
          format_npci_hex(binary)
        end

      1 ->
        Integer.to_string(address)

      _other ->
        format_npci_hex(binary)
    end
  end

  defp npci_address_to_binary(address) do
    int_length = max(1, div(byte_size(Integer.to_string(address, 2)) + 7, 8))
    <<address::integer-size(int_length)-unit(8)>>
  end

  defp format_npci_hex(binary) do
    binary
    |> Base.encode16(case: :upper)
    |> String.graphemes()
    |> Enum.chunk_every(2)
    |> Enum.map_join(":", &Enum.join(&1, ""))
  end

  @doc """
  Derives legacy `ip`/`port` fields and a display label from a destination address.
  """
  @spec destination_meta(term()) :: %{
          ip: String.t() | nil,
          port: pos_integer() | nil,
          label: String.t()
        }
  def destination_meta(address) do
    normalized = normalize_destination(address)

    case normalized do
      {ip, port} when is_tuple(ip) and is_integer(port) ->
        %{ip: format_ip(ip), port: port, label: format_destination(normalized)}

      _other ->
        %{ip: nil, port: nil, label: format_destination(normalized)}
    end
  end

  @spec destination_sort_key(term()) :: term()
  def destination_sort_key(address) do
    case normalize_destination(address) do
      {ip, port} when is_tuple(ip) and is_integer(port) -> {0, ip, port}
      mac when is_integer(mac) -> {1, mac}
      other -> {2, inspect(other)}
    end
  end

  @doc "Formats a discovered device record's BACnet destination for display."
  @spec format_device_address(map()) :: String.t()
  def format_device_address(device) when is_map(device) do
    cond do
      is_binary(device[:address_label]) and device[:address_label] != "" ->
        device[:address_label]

      is_binary(device[:ip]) and is_integer(device[:port]) ->
        "#{device[:ip]}:#{device[:port]}"

      true ->
        format_destination(device[:address])
    end
  end

  @spec default_bbmd_port() :: pos_integer()
  def default_bbmd_port(), do: @bacnet_port

  @spec default_ipv4_port() :: pos_integer()
  def default_ipv4_port(), do: @bacnet_port

  @spec valid_ipv4_port?(integer()) :: boolean()
  def valid_ipv4_port?(port) when is_integer(port), do: port in @ipv4_port_range

  def valid_ipv4_port?(_port), do: false

  defp expand_host_ranges(host) do
    parts = String.split(host, ".")

    if length(parts) != 4 do
      {:error, :invalid_host}
    else
      with {:ok, octet_lists} <- parse_octet_parts(parts) do
        ips =
          octet_lists
          |> cartesian_product()
          |> Enum.map(&List.to_tuple/1)

        cond do
          ips == [] -> {:error, :invalid_host}
          length(ips) > @max_scan_targets -> {:error, {:too_many_targets, @max_scan_targets}}
          true -> {:ok, ips}
        end
      end
    end
  end

  defp parse_octet_parts(parts) do
    case Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
           case parse_octet_part(part) do
             {:ok, values} -> {:cont, {:ok, [values | acc]}}
             {:error, _parts} = err -> {:halt, err}
           end
         end) do
      {:ok, octet_lists} -> {:ok, Enum.reverse(octet_lists)}
      err -> err
    end
  end

  defp parse_octet_part(part) do
    cond do
      Regex.match?(@octet_range_re, part) ->
        [_parts, low_str, high_str] = Regex.run(@octet_range_re, part)
        parse_octet_range(String.to_integer(low_str), String.to_integer(high_str))

      Regex.match?(~r/^\d+$/, part) ->
        part
        |> String.to_integer()
        |> parse_octet()
        |> then(fn
          {:ok, value} -> {:ok, [value]}
          {:error, _reason} = err -> err
        end)

      true ->
        {:error, :invalid_host}
    end
  end

  defp parse_octet_range(low, high) when low > high, do: {:error, :invalid_host}

  defp parse_octet_range(low, high) do
    with :ok <- validate_octet(low),
         :ok <- validate_octet(high) do
      {:ok, Enum.to_list(low..high)}
    end
  end

  defp parse_octet(value) do
    case validate_octet(value) do
      :ok -> {:ok, value}
      {:error, _parts} = err -> err
    end
  end

  defp validate_octet(value) when value in 0..255, do: :ok
  defp validate_octet(_value), do: {:error, :invalid_host}

  defp cartesian_product([first | rest]) do
    rest
    |> Enum.reduce(Enum.map(first, &[&1]), fn values, acc ->
      for prefix <- acc, value <- values, do: [value | prefix]
    end)
    |> Enum.map(&Enum.reverse/1)
  end

  defp cartesian_product([]), do: [[]]
end
