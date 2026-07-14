defmodule BacViewWeb.SubscriptionTable do
  @moduledoc false

  alias BacViewWeb.SearchQuery
  alias BacViewWeb.TableSort

  @sort_columns ~w(object description property last_cov value remaining)

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

  @spec enrich_subscriptions([map()], [map()]) :: [map()]
  def enrich_subscriptions(subscriptions, objects) when is_list(subscriptions) do
    object_meta = object_meta_map(objects)

    Enum.map(subscriptions, fn sub ->
      key = {sub.object_id.type, sub.object_id.instance}

      case Map.get(object_meta, key) do
        %{name: name, description: description} ->
          sub
          |> Map.put(:object_name, name)
          |> Map.put(:description, description)

        nil ->
          sub
          |> Map.put(:object_name, nil)
          |> Map.put(:description, nil)
      end
    end)
  end

  @spec list_subscriptions([map()], [map()], String.t(), String.t() | nil, :asc | :desc) :: [
          map()
        ]
  def list_subscriptions(subscriptions, objects, search, sort_by, sort_dir)
      when is_list(subscriptions) do
    subscriptions
    |> enrich_subscriptions(objects)
    |> filtered_subscriptions(search)
    |> sorted_subscriptions(sort_by, sort_dir)
  end

  @spec filtered_subscriptions([map()], String.t()) :: [map()]
  def filtered_subscriptions(subscriptions, search) when is_list(subscriptions) do
    query = SearchQuery.parse(search)

    Enum.filter(subscriptions, fn sub ->
      SearchQuery.matches?(query, subscription_search_haystack(sub))
    end)
  end

  @spec sorted_subscriptions([map()], String.t() | nil, :asc | :desc) :: [map()]
  def sorted_subscriptions(subscriptions, sort_by, sort_dir) do
    TableSort.sort(subscriptions, sort_by, sort_dir, @sort_columns, &sort_key/2)
  end

  defp sort_key(sub, "object"),
    do: {sub.object_id.type, sub.object_id.instance}

  defp sort_key(sub, "description"),
    do: TableSort.nullable_string_key(Map.get(sub, :description))

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

  defp object_meta_map(objects) when is_list(objects) do
    Map.new(objects, fn obj ->
      {{obj.type, obj.instance}, %{name: object_name(obj), description: object_description(obj)}}
    end)
  end

  defp object_meta_map(_objects), do: %{}

  defp object_name(%{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_name(_object), do: nil

  defp object_description(%{description: description}) when is_binary(description) do
    case String.trim(description) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp object_description(_object), do: nil

  defp subscription_search_haystack(sub) when is_map(sub) do
    %{type: type, instance: instance} = Map.get(sub, :object_id)
    property = Map.get(sub, :property)

    [
      type,
      instance,
      Map.get(sub, :object_name),
      Map.get(sub, :description),
      property,
      Map.get(sub, :last_value_formatted)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &to_string/1)
    |> String.downcase()
  end
end
