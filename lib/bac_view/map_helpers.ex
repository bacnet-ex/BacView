defmodule BacView.MapHelpers do
  @moduledoc """
  Safe map updates for OTP 27+.

  `%{map | key: value}` raises `KeyError` when `key` is not already present.
  Use `update/2` when merging fields into plain maps whose shape may evolve.
  """

  @spec update(map(), map()) :: map()
  def update(map, attrs) when is_map(map) and is_map(attrs), do: Map.merge(map, attrs)
end
