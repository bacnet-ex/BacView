defmodule BacView.Test.BacnetEtsLock do
  @moduledoc false

  alias BacView.Test.BacnetEtsOwner

  # Runtime lock id (avoid compile-time node/0 in the lock term).
  @lock_key :bacview_ets_test_lock

  @default_table_opts [:named_table, :set, :public]

  @doc """
  Ensures the given named ETS tables exist (owned by `BacnetEtsOwner`), empties
  them, runs `fun`, then empties them again.

  Tables are **not** created in the test process — ownership stays with the
  suite-lifetime owner so async test process exits cannot drop tables mid-run
  for other tests.

  Serializes access across async tests that share global BACnet cache tables.

  Specs may be `{table, opts}` tuples or bare table atoms (default opts:
  `#{inspect(@default_table_opts)}`).
  """
  @spec with_tables([atom() | {atom(), [atom() | tuple()]}], (-> term())) :: term()
  def with_tables(table_specs, fun) when is_function(fun, 0) do
    specs = normalize_specs(table_specs)

    trans(fn ->
      BacnetEtsOwner.ensure_tables!(specs)

      try do
        fun.()
      after
        BacnetEtsOwner.clear_tables!(specs)
      end
    end)
  end

  @doc """
  Ensures tables exist under `BacnetEtsOwner` and are empty (takes the global
  ETS lock).
  """
  @spec reset_tables!([atom() | {atom(), [atom() | tuple()]}]) :: :ok
  def reset_tables!(table_specs) do
    specs = normalize_specs(table_specs)
    trans(fn -> BacnetEtsOwner.ensure_tables!(specs) end)
  end

  @doc """
  Empties tables if present. Prefer this over deleting named tables so other
  async tests do not observe a missing name.
  """
  @spec delete_tables!([atom() | {atom(), [atom() | tuple()]}]) :: :ok
  def delete_tables!(table_specs) do
    specs = normalize_specs(table_specs)
    trans(fn -> BacnetEtsOwner.clear_tables!(specs) end)
  end

  defp normalize_specs(table_specs) when is_list(table_specs) do
    Enum.map(table_specs, fn
      {table, opts} when is_atom(table) and is_list(opts) -> {table, opts}
      table when is_atom(table) -> {table, @default_table_opts}
    end)
  end

  defp trans(fun) do
    :global.trans({@lock_key, node()}, fun, [node()], :infinity)
  end
end
