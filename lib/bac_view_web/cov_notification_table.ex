defmodule BacViewWeb.CovNotificationTable do
  @moduledoc false

  alias BacViewWeb.TableSort

  @sort_columns ~w(received object property value confirmed time_remaining)
  @default_sort_by "received"
  @default_sort_dir :desc

  @spec sort_columns() :: [String.t()]
  def sort_columns(), do: @sort_columns

  @spec default_sort_by() :: String.t()
  def default_sort_by(), do: @default_sort_by

  @spec default_sort_dir() :: :asc | :desc
  def default_sort_dir(), do: @default_sort_dir

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

  @spec sorted_notifications([map()], String.t() | nil, :asc | :desc | nil) :: [map()]
  def sorted_notifications(notifications, sort_by, sort_dir) do
    sort_by = sort_by || @default_sort_by
    sort_dir = sort_dir || @default_sort_dir

    TableSort.sort(notifications, sort_by, sort_dir, @sort_columns, &sort_key/2)
  end

  defp sort_key(entry, "received"),
    do: TableSort.datetime_key(Map.get(entry, :received_at))

  defp sort_key(entry, "object"),
    do: {entry.object_id.type, entry.object_id.instance}

  defp sort_key(entry, "property"), do: property_sort_key(entry.property)

  defp sort_key(entry, "value"),
    do: TableSort.nullable_string_key(Map.get(entry, :formatted))

  defp sort_key(entry, "confirmed"),
    do: if(Map.get(entry, :confirmed), do: 0, else: 1)

  defp sort_key(entry, "time_remaining"),
    do: Map.get(entry, :time_remaining) || -1

  defp property_sort_key(property) when is_atom(property),
    do: TableSort.nullable_string_key(Atom.to_string(property))

  defp property_sort_key(property) when is_integer(property), do: property
  defp property_sort_key(property), do: TableSort.nullable_string_key(to_string(property))
end
