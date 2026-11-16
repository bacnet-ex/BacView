defmodule BacView.BACnet.Address do
  @moduledoc """
  Parses BACnet/IP host and port values and formats transport-layer destination
  addresses for display and comparison.
  """

  alias BACnet.Protocol.NpciTarget
  alias BACnet.Protocol.SecureConnect.BVLC

  @bacnet_port 47_808
  @ipv4_port_range 47_808..65_535
  @mstp_unicast_range 0..254
  @max_scan_targets 256
  @octet_range_re ~r/^\[(\d+)-(\d+)\]$/
  @npci_hex_re ~r/\A[0-9a-f]{2}(?::[0-9a-f]{2}){1,6}\z/i

  @doc "Checks whether a target is an encodable remote station address."
  defguard is_npci_station(target)
           when is_struct(target, NpciTarget) and target.net in 1..65_534 and
                  is_integer(target.address) and target.address in 0..0xFFFFFFFFFFFFFF

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
  Parses a user-entered destination for the active stack transport.

  * `"ipv4"` - IPv4 host, optional `:port` (default #{@bacnet_port})
  * `"mstp"` - unicast MS/TP MAC in `0..254` (255 is broadcast)
  * `"bacnet_sc"` - six-octet unicast VMAC in colon-separated hex
  """
  @spec parse_transport_destination(String.t(), String.t()) ::
          {:ok, {:inet.ip_address(), pos_integer()} | 0..254 | BVLC.vmac()}
          | {:error,
             :invalid_host
             | :invalid_port
             | :invalid_mstp_address
             | :invalid_sc_vmac
             | :unsupported_transport}
  def parse_transport_destination(value, transport)

  def parse_transport_destination(value, "ipv4") when is_binary(value) do
    parse_ipv4_destination(String.trim(value))
  end

  def parse_transport_destination(value, "mstp") when is_binary(value) do
    parse_mstp_destination(String.trim(value))
  end

  def parse_transport_destination(value, "bacnet_sc") when is_binary(value) do
    value = String.trim(value)

    with true <- Regex.match?(~r/\A[0-9a-f]{2}(?::[0-9a-f]{2}){5}\z/i, value),
         {:ok, vmac} <- Base.decode16(String.replace(value, ":", ""), case: :mixed),
         true <- BVLC.valid_vmac?(vmac) do
      {:ok, vmac}
    else
      _reason -> {:error, :invalid_sc_vmac}
    end
  end

  def parse_transport_destination(_value, _transport), do: {:error, :unsupported_transport}

  @doc """
  Parses an optional remote station as `network/address`.

  The address accepts a decimal MS/TP MAC, an IPv4 address with optional port,
  or two to seven colon-separated hex octets. The remote address format is
  independent of the active transport used to reach the router.
  """
  @spec parse_npci_station(term()) :: {:ok, NpciTarget.t() | nil} | {:error, :invalid_npci_source}
  def parse_npci_station(nil), do: {:ok, nil}

  def parse_npci_station(value) when is_binary(value) do
    case String.split(String.trim(value), "/", parts: 2) do
      [""] -> {:ok, nil}
      [network, address] -> parse_npci_station_parts(String.trim(network), String.trim(address))
      _parts -> {:error, :invalid_npci_source}
    end
  end

  def parse_npci_station(_value), do: {:error, :invalid_npci_source}

  defp parse_npci_station_parts(network, address) do
    with {net, ""} when net in 1..65_534 <- Integer.parse(network),
         {:ok, mac} <- parse_npci_station_address(address) do
      {:ok, %NpciTarget{net: net, address: mac}}
    else
      _reason -> {:error, :invalid_npci_source}
    end
  end

  defp parse_npci_station_address(address) do
    cond do
      String.contains?(address, ".") ->
        with {:ok, {{a, b, c, d}, port}} when a > 0 <- parse_ipv4_destination(address) do
          {:ok, :binary.decode_unsigned(<<a, b, c, d, port::16>>)}
        end

      Regex.match?(@npci_hex_re, address) ->
        # Bacstack encodes integer addresses with the minimum number of bytes.
        case Base.decode16(String.replace(address, ":", ""), case: :mixed) do
          {:ok, <<first, _rest::binary>> = bytes} when first > 0 ->
            {:ok, :binary.decode_unsigned(bytes)}

          _bytes ->
            :error
        end

      true ->
        parse_mstp_destination(address)
    end
  end

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

  @doc """
  Expands a Who-Is scan target into `{ip, port}` destinations.

  Plain hosts and octet ranges use `default_port`. A trailing `:port`
  (`192.168.1.101:47808`, `192.168.100.[31-35]:47809`) overrides that port for
  every expanded address.
  """
  @spec expand_scan_destinations(String.t(), 1..65_535) ::
          {:ok, [{:inet.ip_address(), 1..65_535}]}
          | {:error, :invalid_host | :invalid_port | {:too_many_targets, pos_integer()}}
  def expand_scan_destinations(value, default_port)
      when is_binary(value) and default_port in 1..65_535 do
    {host, port_source} = split_optional_port(String.trim(value))

    with {:ok, port} <- resolve_scan_port(port_source, default_port),
         {:ok, ips} <- expand_scan_targets(host) do
      {:ok, Enum.map(ips, &{&1, port})}
    end
  end

  def expand_scan_destinations(_value, _default_port), do: {:error, :invalid_host}

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
  def format_destination(<<_mac::48>> = vmac), do: format_npci_hex(vmac)
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
      <<_mac::48>> = vmac -> {2, vmac}
      other -> {3, inspect(other)}
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

  defp split_optional_port(value) do
    case String.split(value, ":", parts: 2) do
      [host, port] -> {String.trim(host), {:explicit, String.trim(port)}}
      [host] -> {String.trim(host), :default}
    end
  end

  defp resolve_scan_port(:default, default_port), do: {:ok, default_port}

  defp resolve_scan_port({:explicit, port}, _default_port), do: parse_port(port)

  defp parse_ipv4_destination(""), do: {:error, :invalid_host}

  defp parse_ipv4_destination(value) do
    case String.split(value, ":", parts: 2) do
      [host] ->
        case parse_host(host) do
          {:ok, ip} -> {:ok, {ip, default_ipv4_port()}}
          {:error, _host} = err -> err
        end

      [host, port] ->
        with {:ok, ip} <- parse_host(host),
             {:ok, parsed_port} <- parse_port(port) do
          {:ok, {ip, parsed_port}}
        end
    end
  end

  defp parse_mstp_destination(""), do: {:error, :invalid_mstp_address}

  defp parse_mstp_destination(value) do
    case Integer.parse(value) do
      {mac, ""} when mac in @mstp_unicast_range -> {:ok, mac}
      _mac -> {:error, :invalid_mstp_address}
    end
  end

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
