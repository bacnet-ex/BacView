defmodule BacView.Test.BacnetEtsLock do
  @moduledoc false

  @lock {:bacview_ets_test_lock, node()}

  @default_table_opts [:named_table, :set, :public]

  @doc """
  Resets the given named ETS tables, runs `fun`, then deletes them.

  Serializes access across async tests that share global BACnet cache tables.

  Specs may be `{table, opts}` tuples or bare table atoms (default opts:
  `#{inspect(@default_table_opts)}`).
  """
  @spec with_tables([atom() | {atom(), [atom() | tuple()]}], (-> term())) :: term()
  def with_tables(table_specs, fun) when is_function(fun, 0) do
    specs = normalize_specs(table_specs)

    trans(fn ->
      reset_tables!(specs)

      try do
        fun.()
      after
        delete_tables!(specs)
      end
    end)
  end

  @spec reset_tables!([atom() | {atom(), [atom() | tuple()]}]) :: :ok
  def reset_tables!(table_specs) do
    specs = normalize_specs(table_specs)
    delete_tables!(specs)

    for {table, opts} <- specs do
      :ets.new(table, opts)
    end

    :ok
  end

  @spec delete_tables!([atom() | {atom(), [atom() | tuple()]}]) :: :ok
  def delete_tables!(table_specs) do
    for {table, _opts} <- normalize_specs(table_specs) do
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end

    :ok
  end

  defp normalize_specs(table_specs) when is_list(table_specs) do
    Enum.map(table_specs, fn
      {table, opts} when is_atom(table) and is_list(opts) -> {table, opts}
      table when is_atom(table) -> {table, @default_table_opts}
    end)
  end

  defp trans(fun) do
    :global.trans(@lock, fun, [node()], :infinity)
  end
end
