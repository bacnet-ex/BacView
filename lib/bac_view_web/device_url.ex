defmodule BacViewWeb.DeviceUrl do
  @moduledoc false

  use BacViewWeb, :verified_routes

  alias BacView.BACnet.HierarchySplit
  alias BacViewWeb.ObjectTable

  @default_tab "hierarchy"
  @default_alarm_view "event_information"
  @default_cov_view "subscriptions"
  @default_hierarchy_view "explorer"
  @valid_tabs ~w(hierarchy objects subscriptions alarms)
  @valid_alarm_views ~w(event_information active_alarms notifications)
  @valid_cov_views ~w(subscriptions notifications)
  @valid_hierarchy_views ~w(explorer tree)

  def device_path(device_id, opts \\ []) do
    tab = normalize_tab(Keyword.get(opts, :tab, @default_tab))
    alarm_view = normalize_alarm_view(Keyword.get(opts, :alarm_view))
    cov_view = normalize_cov_view(Keyword.get(opts, :cov_view))
    hierarchy_view = normalize_hierarchy_view(Keyword.get(opts, :hierarchy_view))
    hierarchy_path = normalize_hierarchy_path(Keyword.get(opts, :hierarchy_path))
    hierarchy_split = normalize_hierarchy_split(Keyword.get(opts, :h_split))

    case device_query(
           tab,
           alarm_view,
           cov_view,
           hierarchy_view,
           hierarchy_path,
           hierarchy_split,
           opts
         ) do
      nil -> ~p"/devices/#{device_id}"
      query -> ~p"/devices/#{device_id}?#{query}"
    end
  end

  def object_path(device_id, type, instance, opts \\ []) do
    case list_state_query(opts) do
      nil ->
        ~p"/devices/#{device_id}/objects/#{type}/#{instance}"

      query ->
        ~p"/devices/#{device_id}/objects/#{type}/#{instance}?#{query}"
    end
  end

  def device_object_path(device_id, %{instance: instance}, opts \\ []) do
    object_path(device_id, :device, instance, opts)
  end

  def normalize_search(nil), do: ""
  def normalize_search(search) when is_binary(search), do: search
  def normalize_search(_nil), do: ""

  def normalize_types(nil), do: []
  def normalize_types(""), do: []

  def normalize_types(types) when is_binary(types) do
    types
    |> String.split(",", trim: true)
    |> Enum.flat_map(&parse_type_atom/1)
  end

  def normalize_types(types) when is_list(types) do
    types
    |> Enum.flat_map(fn
      type when is_atom(type) -> [type]
      type when is_binary(type) -> parse_type_atom(type)
      _nil -> []
    end)
    |> Enum.uniq()
  end

  def normalize_types(_nil), do: []

  def normalize_sort_column(column) do
    ObjectTable.normalize_sort_column(column)
  end

  def normalize_sort_dir(dir) do
    ObjectTable.normalize_sort_dir(dir)
  end

  def encode_types(types) when is_list(types) do
    types
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
    |> Enum.join(",")
  end

  def normalize_status(nil), do: []
  def normalize_status(""), do: []

  def normalize_status(status) when is_binary(status) do
    status
    |> String.split(",", trim: true)
    |> Enum.map(&ObjectTable.normalize_status_flag/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def normalize_status(status) when is_list(status) do
    status
    |> Enum.flat_map(fn
      flag when is_atom(flag) -> [ObjectTable.normalize_status_flag(flag)]
      flag when is_binary(flag) -> [ObjectTable.normalize_status_flag(flag)]
      _nil -> []
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def normalize_status(_nil), do: []

  def encode_status(status) when is_list(status), do: ObjectTable.encode_status_flags(status)

  def normalize_tab(nil), do: @default_tab

  def normalize_tab(tab) when tab in @valid_tabs, do: tab

  def normalize_tab(tab) when is_binary(tab) do
    if tab in @valid_tabs, do: tab, else: @default_tab
  end

  def normalize_tab(tab) when is_atom(tab), do: normalize_tab(Atom.to_string(tab))
  def normalize_tab(_nil), do: @default_tab

  def normalize_alarm_view(nil), do: @default_alarm_view

  def normalize_alarm_view(view) when is_binary(view) do
    if view in @valid_alarm_views, do: view, else: @default_alarm_view
  end

  def normalize_alarm_view(view) when is_atom(view) do
    normalize_alarm_view(Atom.to_string(view))
  end

  def normalize_alarm_view(_nil), do: @default_alarm_view

  def normalize_cov_view(nil), do: @default_cov_view

  def normalize_cov_view(view) when is_binary(view) do
    if view in @valid_cov_views, do: view, else: @default_cov_view
  end

  def normalize_cov_view(view) when is_atom(view), do: normalize_cov_view(Atom.to_string(view))
  def normalize_cov_view(_nil), do: @default_cov_view

  def normalize_hierarchy_view(nil), do: @default_hierarchy_view

  def normalize_hierarchy_view(view) when view in @valid_hierarchy_views, do: view

  def normalize_hierarchy_view(view) when is_binary(view) do
    if view in @valid_hierarchy_views, do: view, else: @default_hierarchy_view
  end

  def normalize_hierarchy_view(view) when is_atom(view),
    do: normalize_hierarchy_view(Atom.to_string(view))

  def normalize_hierarchy_view(_nil), do: @default_hierarchy_view

  def normalize_hierarchy_path(nil), do: []

  def normalize_hierarchy_path(path) when is_binary(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.flat_map(&decode_hierarchy_segment/1)
  end

  def normalize_hierarchy_path(path) when is_list(path), do: path
  def normalize_hierarchy_path(_nil), do: []

  def encode_hierarchy_path([]), do: nil

  def encode_hierarchy_path(path) when is_list(path) do
    Enum.map_join(path, "/", fn {type, instance} -> "#{type}:#{instance}" end)
  end

  def normalize_hierarchy_split(nil), do: nil
  def normalize_hierarchy_split(split), do: HierarchySplit.normalize(split)

  def encode_sort_dir(:asc), do: "asc"
  def encode_sort_dir(:desc), do: "desc"
  def encode_sort_dir("asc"), do: "asc"
  def encode_sort_dir("desc"), do: "desc"
  def encode_sort_dir(_asc), do: "asc"

  defp device_query(
         tab,
         alarm_view,
         cov_view,
         hierarchy_view,
         hierarchy_path,
         hierarchy_split,
         opts
       ) do
    []
    |> maybe_param(:tab, tab, tab != @default_tab)
    |> append_hierarchy_params(tab, hierarchy_view, hierarchy_path, hierarchy_split)
    |> maybe_param(
      :alarm_view,
      alarm_view,
      tab == "alarms" and alarm_view != @default_alarm_view
    )
    |> maybe_param(
      :cov_view,
      cov_view,
      tab == "subscriptions" and cov_view != @default_cov_view
    )
    |> append_list_state_params(opts)
    |> query_or_nil()
  end

  defp list_state_query(opts) do
    tab = normalize_tab(Keyword.get(opts, :tab, @default_tab))
    alarm_view = normalize_alarm_view(Keyword.get(opts, :alarm_view))
    cov_view = normalize_cov_view(Keyword.get(opts, :cov_view))
    hierarchy_view = normalize_hierarchy_view(Keyword.get(opts, :hierarchy_view))
    hierarchy_path = normalize_hierarchy_path(Keyword.get(opts, :hierarchy_path))
    hierarchy_split = normalize_hierarchy_split(Keyword.get(opts, :h_split))

    []
    |> maybe_param(:tab, tab, tab != @default_tab)
    |> append_hierarchy_params(tab, hierarchy_view, hierarchy_path, hierarchy_split)
    |> maybe_param(
      :alarm_view,
      alarm_view,
      tab == "alarms" and alarm_view != @default_alarm_view
    )
    |> maybe_param(
      :cov_view,
      cov_view,
      tab == "subscriptions" and cov_view != @default_cov_view
    )
    |> append_list_state_params(opts)
    |> query_or_nil()
  end

  defp append_hierarchy_params(params, tab, hierarchy_view, hierarchy_path, hierarchy_split) do
    params
    |> maybe_param(
      :hierarchy_view,
      hierarchy_view,
      tab == "hierarchy" and hierarchy_view != @default_hierarchy_view
    )
    |> maybe_param(
      :h_path,
      encode_hierarchy_path(hierarchy_path),
      tab == "hierarchy" and hierarchy_path != []
    )
    |> maybe_param(
      :h_split,
      HierarchySplit.encode(hierarchy_split),
      tab == "hierarchy" and hierarchy_split != nil
    )
  end

  defp decode_hierarchy_segment(segment) when is_binary(segment) do
    case String.split(segment, ":", parts: 2) do
      [type, instance_str] ->
        with [type_atom] <- parse_type_atom(type),
             {instance, ""} <- Integer.parse(instance_str) do
          [{type_atom, instance}]
        else
          _segment -> []
        end

      _segment ->
        []
    end
  end

  defp append_list_state_params(params, opts) do
    search = normalize_search(Keyword.get(opts, :search, ""))
    types = normalize_types(Keyword.get(opts, :types, []))
    status = normalize_status(Keyword.get(opts, :status, []))
    sort_by = normalize_sort_column(Keyword.get(opts, :sort, nil))
    sort_dir = normalize_sort_dir(Keyword.get(opts, :dir, nil))

    params
    |> maybe_param(:search, search, search != "")
    |> maybe_param(:types, encode_types(types), types != [])
    |> maybe_param(:status, encode_status(status), status != [])
    |> maybe_param(:sort, sort_by, is_binary(sort_by))
    |> maybe_param(:dir, encode_sort_dir(sort_dir), is_binary(sort_by))
  end

  defp query_or_nil([]), do: nil
  defp query_or_nil(params), do: Enum.reverse(params)

  defp maybe_param(params, key, value, true), do: [{key, value} | params]

  defp maybe_param(params, _key, _value, false), do: params

  defp parse_type_atom(type) when is_binary(type) do
    case String.to_existing_atom(type) do
      atom -> [atom]
    end
  rescue
    ArgumentError -> []
  end
end
