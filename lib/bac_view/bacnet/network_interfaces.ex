defmodule BacView.BACnet.NetworkInterfaces do
  @moduledoc false

  @type option :: %{
          value: String.t(),
          label: String.t(),
          name: String.t(),
          address: :inet.ip4_address()
        }

  @spec list() :: [option()]
  def list() do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        ifaddrs
        |> Enum.flat_map(&interface_options/1)
        |> Enum.uniq_by(& &1.value)
        |> Enum.sort_by(& &1.label, :asc)

      {:error, _list} ->
        []
    end
  end

  @spec format_ip(:inet.ip4_address()) :: String.t()
  def format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp interface_options({name, opts}) when is_list(name),
    do: interface_options({to_string(name), opts})

  defp interface_options({name, opts}) do
    name = to_string(name)

    opts
    |> Keyword.get_values(:addr)
    |> Enum.flat_map(fn
      {:inet, {a, b, c, d}} ->
        [interface_option(name, {a, b, c, d})]

      {a, b, c, d} when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) ->
        [interface_option(name, {a, b, c, d})]

      _name ->
        []
    end)
  end

  defp interface_option(name, ip4) do
    %{
      value: name,
      label: "#{name} — #{format_ip(ip4)}",
      name: name,
      address: ip4
    }
  end
end
