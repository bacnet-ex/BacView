defmodule BacView.NaturalSort do
  @moduledoc false

  @segment_pattern ~r/\d+|\D+/

  @spec key(String.t() | nil) :: [term()]
  def key(nil), do: []

  def key(value) when is_binary(value) do
    value
    |> String.downcase()
    |> tokenize()
  end

  def key(value), do: key(to_string(value))

  defp tokenize(string) do
    @segment_pattern
    |> Regex.scan(string)
    |> Enum.map(&segment_key/1)
  end

  defp segment_key([segment]) do
    case Integer.parse(segment) do
      {int, ""} -> int
      _segment_key -> segment
    end
  end
end
