defmodule BacViewWeb.TableSort do
  @moduledoc false

  alias BacView.NaturalSort

  @spec normalize_dir(term()) :: :asc | :desc
  def normalize_dir(dir) when dir in [:asc, :desc], do: dir
  def normalize_dir("asc"), do: :asc
  def normalize_dir("desc"), do: :desc
  def normalize_dir(_dir), do: :asc

  @spec toggle_sort(String.t() | nil, :asc | :desc, String.t()) :: {String.t(), :asc | :desc}
  def toggle_sort(nil, _sort_dir, column), do: {column, :asc}
  def toggle_sort(column, :asc, column), do: {column, :desc}
  def toggle_sort(column, :desc, column), do: {column, :asc}
  def toggle_sort(_sort_by, _sort_dir, column), do: {column, :asc}

  @spec sort(list(), String.t() | nil, :asc | :desc, [String.t()], (term(), String.t() -> term())) ::
          list()
  def sort(items, sort_by, sort_dir, columns, sort_key_fun)
      when is_list(items) and is_function(sort_key_fun, 2) do
    if sort_by in columns do
      Enum.sort_by(items, &sort_key_fun.(&1, sort_by), sort_dir)
    else
      items
    end
  end

  @doc false
  @spec nullable_string_key(String.t() | nil) :: [term()]
  def nullable_string_key(nil), do: NaturalSort.key("")
  def nullable_string_key(value) when is_binary(value), do: NaturalSort.key(value)
  def nullable_string_key(value), do: NaturalSort.key(value)

  @doc false
  @spec datetime_key(DateTime.t() | nil) :: integer()
  def datetime_key(nil), do: 0

  def datetime_key(%DateTime{} = dt),
    do: DateTime.to_unix(dt, :microsecond)
end
