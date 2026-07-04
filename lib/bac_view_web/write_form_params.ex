defmodule BacViewWeb.WriteFormParams do
  @moduledoc false

  @spec normalize(map()) :: map()
  def normalize(params) when is_map(params) do
    Map.get(params, "write", params)
  end

  @spec priority(map(), 1..16) :: 1..16
  def priority(params, default) when is_map(params) and default in 1..16 do
    params
    |> normalize()
    |> Map.get("priority")
    |> parse_priority()
    |> case do
      p when p in 1..16 -> p
      _params -> default
    end
  end

  @spec parse_priority(term()) :: 1..16 | nil
  def parse_priority(priority) when priority in 1..16, do: priority

  def parse_priority(priority) when is_binary(priority) do
    case Integer.parse(priority) do
      {p, ""} when p in 1..16 -> p
      _priority -> nil
    end
  end

  def parse_priority(_priority), do: nil
end
