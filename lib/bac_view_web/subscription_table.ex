defmodule BacViewWeb.SubscriptionTable do
  @moduledoc false

  alias BacViewWeb.TableSort

  @sort_columns ~w(object property last_cov value remaining)

  @spec sort_columns() :: [String.t()]
  def sort_columns(), do: @sort_columns

  @spec normalize_sort_column(term()) :: String.t() | nil
  def normalize_sort_column(column) when column in @sort_columns, do: column

  def normalize_sort_column(column) when is_atom(column),
    do: normalize_sort_column(Atom.to_string(column))

  def normalize_sort_column(_column), do: nil

  @spec normalize_sort_dir(term()) :: :asc | :desc
  def normalize_sort_dir(dir), do: TableSort.normalize_dir(dir)

  @spec toggle_sort(String.t() | nil, :asc | :desc, String.t()) :: {String.t(), :asc | :desc}
  def toggle_sort(sort_by, sort_dir, column),
    do: TableSort.toggle_sort(sort_by, sort_dir, column)

  @spec sorted_subscriptions([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_subscriptions(subscriptions, sort_by, sort_dir) do
    TableSort.sort(subscriptions, sort_by, sort_dir, @sort_columns, &sort_key/2)
  end

  defp sort_key(sub, "object"),
    do: {sub.object_id.type, sub.object_id.instance}

  defp sort_key(sub, "property"), do: property_sort_key(sub.property)

  defp sort_key(sub, "last_cov"),
    do: TableSort.datetime_key(Map.get(sub, :last_cov_at))

  defp sort_key(sub, "value"),
    do: TableSort.nullable_string_key(Map.get(sub, :last_value_formatted))

  defp sort_key(sub, "remaining"), do: remaining_sort_key(sub)

  defp property_sort_key(property) when is_atom(property),
    do: TableSort.nullable_string_key(Atom.to_string(property))

  defp property_sort_key(property) when is_integer(property), do: property
  defp property_sort_key(property), do: TableSort.nullable_string_key(to_string(property))

  defp remaining_sort_key(%{lifetime: 0}), do: {0, :unlimited}
  defp remaining_sort_key(%{expires_at: nil}), do: {1, 0}

  defp remaining_sort_key(%{expires_at: expires_at}) do
    {2, max(0, DateTime.diff(expires_at, DateTime.utc_now(), :second))}
  end
end
