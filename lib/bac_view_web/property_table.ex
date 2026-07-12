defmodule BacViewWeb.PropertyTable do
  @moduledoc false

  alias BacViewWeb.TableSort

  @sort_columns ~w(name value type actions)
  @unknown_sort_columns ~w(name value type)

  @spec sort_columns() :: [String.t()]
  def sort_columns(), do: @sort_columns

  @spec unknown_sort_columns() :: [String.t()]
  def unknown_sort_columns(), do: @unknown_sort_columns

  @spec normalize_sort_column(term()) :: String.t() | nil
  def normalize_sort_column(column) when column in @sort_columns, do: column

  def normalize_sort_column(column) when is_atom(column),
    do: normalize_sort_column(Atom.to_string(column))

  def normalize_sort_column(_column), do: nil

  @spec normalize_unknown_sort_column(term()) :: String.t() | nil
  def normalize_unknown_sort_column(column) when column in @unknown_sort_columns, do: column

  def normalize_unknown_sort_column(column) when is_atom(column),
    do: normalize_unknown_sort_column(Atom.to_string(column))

  def normalize_unknown_sort_column(_column), do: nil

  @spec normalize_sort_dir(term()) :: :asc | :desc
  def normalize_sort_dir(dir), do: TableSort.normalize_dir(dir)

  @spec toggle_sort(String.t() | nil, :asc | :desc, String.t()) :: {String.t(), :asc | :desc}
  def toggle_sort(sort_by, sort_dir, column),
    do: TableSort.toggle_sort(sort_by, sort_dir, column)

  @spec sorted_properties([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_properties(properties, sort_by, sort_dir) do
    TableSort.sort(properties, sort_by, sort_dir, @sort_columns, &sort_key/2)
  end

  @spec sorted_unknown_properties([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_unknown_properties(properties, sort_by, sort_dir) do
    TableSort.sort(properties, sort_by, sort_dir, @unknown_sort_columns, &unknown_sort_key/2)
  end

  defp sort_key(prop, "name"),
    do: TableSort.nullable_string_key(Map.get(prop, :property_name))

  defp sort_key(prop, "value"), do: TableSort.nullable_string_key(value_sort_key(prop))
  defp sort_key(prop, "type"), do: TableSort.nullable_string_key(Map.get(prop, :type))
  defp sort_key(prop, "actions"), do: {actions_sort_key(prop), Map.get(prop, :property)}

  defp unknown_sort_key(prop, column), do: sort_key(prop, column)

  defp value_sort_key(%{value_formatted: formatted}) when is_binary(formatted), do: formatted

  defp value_sort_key(%{value_display: %{formatted: formatted}}) when is_binary(formatted),
    do: formatted

  defp value_sort_key(_formatted), do: nil

  defp actions_sort_key(prop) do
    writable = Map.get(prop, :writable, false)
    if writable, do: 0, else: 1
  end
end
