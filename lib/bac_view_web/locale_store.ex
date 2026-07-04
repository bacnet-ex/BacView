defmodule BacViewWeb.LocaleStore do
  @moduledoc false

  @table :bacview_locale_store

  @spec init() :: :ok
  def init() do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end

    :ok
  end

  @spec put(pid(), String.t()) :: :ok
  def put(transport_pid, locale) when is_pid(transport_pid) and is_binary(locale) do
    init()
    :ets.insert(@table, {transport_pid, locale})
    :ok
  end

  @spec get(pid()) :: String.t() | nil
  def get(transport_pid) when is_pid(transport_pid) do
    init()

    case :ets.lookup(@table, transport_pid) do
      [{^transport_pid, locale}] -> locale
      _transport_pid -> nil
    end
  end
end
