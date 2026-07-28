defmodule BacView.Test.BacnetEtsOwner do
  @moduledoc """
  Long-lived owner of named BACnet ETS tables used in tests.

  ETS named tables are deleted when their **owner process** exits. Creating them
  in an async test process is unsafe: that process can finish and take the table
  with it while another test still holds a logical "lock" and expects the table
  to exist.

  This GenServer is started from `test_helper.exs` and is the only process that
  should `:ets.new/2` the shared cache tables.
  """
  use GenServer

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures each table exists and is owned by this process, then empties it.

  If a table exists but is owned by another (test) process, it is deleted and
  recreated so ownership moves here for the rest of the suite.
  """
  @spec ensure_tables!([{atom(), keyword()}]) :: :ok
  def ensure_tables!(specs) when is_list(specs) do
    GenServer.call(__MODULE__, {:ensure_tables, specs}, :infinity)
  end

  @doc """
  Empties tables if present (does not delete them).
  """
  @spec clear_tables!([{atom(), keyword()} | atom()]) :: :ok
  def clear_tables!(specs) when is_list(specs) do
    GenServer.call(__MODULE__, {:clear_tables, specs}, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:ensure_tables, specs}, _from, state) do
    Enum.each(specs, &ensure_table/1)
    {:reply, :ok, state}
  end

  def handle_call({:clear_tables, specs}, _from, state) do
    Enum.each(specs, fn
      {table, _opts} when is_atom(table) -> clear_table(table)
      table when is_atom(table) -> clear_table(table)
    end)

    {:reply, :ok, state}
  end

  defp ensure_table({table, opts}) when is_atom(table) and is_list(opts) do
    opts = normalize_opts(opts)

    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, opts)
        :ok

      tid ->
        case :ets.info(tid, :owner) do
          owner when owner == self() ->
            :ets.delete_all_objects(table)
            :ok

          _other_owner ->
            # Public named tables can be deleted from any process; recreate so
            # *this* long-lived process owns the name for the suite lifetime.
            :ets.delete(table)
            :ets.new(table, opts)
            :ok
        end
    end
  end

  defp clear_table(table) when is_atom(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    :ok
  end

  defp normalize_opts(opts) do
    if :named_table in opts do
      opts
    else
      [:named_table | opts]
    end
  end
end
