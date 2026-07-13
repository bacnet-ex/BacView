defmodule BacView.Test.BacnetEtsLock do
  @moduledoc false

  @lock {:bacview_ets_test_lock, node()}

  @doc """
  Resets the given named ETS tables, runs `fun`, then deletes them.

  Serializes access across async tests that share global BACnet cache tables.
  """
  @spec with_tables([{atom(), [atom() | tuple()]}], (-> term())) :: term()
  def with_tables(table_specs, fun) when is_function(fun, 0) do
    trans(fn ->
      reset_tables!(table_specs)

      try do
        fun.()
      after
        delete_tables!(table_specs)
      end
    end)
  end

  @spec reset_tables!([{atom(), [atom() | tuple()]}]) :: :ok
  def reset_tables!(table_specs) do
    delete_tables!(table_specs)

    for {table, opts} <- table_specs do
      :ets.new(table, opts)
    end

    :ok
  end

  @spec delete_tables!([{atom(), [atom() | tuple()]}]) :: :ok
  def delete_tables!(table_specs) do
    for {table, _opts} <- table_specs do
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end

    :ok
  end

  defp trans(fun) do
    :global.trans(@lock, fun, [node()], :infinity)
  end
end
