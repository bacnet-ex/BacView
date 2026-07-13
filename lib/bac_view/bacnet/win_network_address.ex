defmodule BacView.BACnet.WinNetworkAddress do
  @moduledoc false

  @netsh_command ["cmd", "/c", "netsh interface ipv4 show addresses"]
  @ip_address_line ~r/(?:IP Address|IP-Adresse)\s*:\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/i

  @spec friendly_names_by_ip() :: %{String.t() => String.t()}
  def friendly_names_by_ip() do
    case System.cmd(hd(@netsh_command), tl(@netsh_command)) do
      {output, 0} -> parse_netsh_output(output)
      {_output, _exit_code} -> %{}
    end
  end

  @spec parse_netsh_output(String.t()) :: %{String.t() => String.t()}
  def parse_netsh_output(output) when is_binary(output) do
    output
    |> String.split(["\r\n", "\n"])
    |> parse_lines(nil, %{})
  end

  defp parse_lines([], _current, acc), do: acc

  defp parse_lines([line | rest], current, acc) do
    cond do
      String.contains?(line, "\"") ->
        parse_lines(rest, extract_quoted_name(line) || current, acc)

      current != nil ->
        parse_lines(rest, current, maybe_put_ip(acc, current, line))

      true ->
        parse_lines(rest, current, acc)
    end
  end

  defp extract_quoted_name(line) do
    case String.split(line, "\"", parts: 2) do
      [_before, remainder] ->
        case String.split(remainder, "\"", parts: 2) do
          [friendly_name, _after] -> friendly_name
          _no_match -> nil
        end

      _no_quote ->
        nil
    end
  end

  defp maybe_put_ip(acc, friendly_name, line) do
    case Regex.run(@ip_address_line, line) do
      [_full_match, ip] -> Map.put(acc, ip, friendly_name)
      _no_match -> acc
    end
  end
end
