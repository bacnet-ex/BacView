defmodule BacView.BACnet.Address do
  @moduledoc """
  Parses BACnet/IP host and port values.
  """

  @bacnet_port 47_808
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

  @spec default_bbmd_port() :: pos_integer()
  def default_bbmd_port(), do: @bacnet_port

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
