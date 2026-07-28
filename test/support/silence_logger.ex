defmodule BacView.Test.SilenceLogger do
  @moduledoc false

  # Runtime lock id (not compile-time node/0) so module-level changes stay
  # serialized across async tests on the test node.
  @lock_key :bacview_logger_module_level_lock
  @counts_key :bacview_logger_silence_counts

  @doc """
  Raises the log level for `module` for the current test and restores it on exit.

  Concurrent callers are refcounted so one test's `on_exit` does not clear the
  override while another test still expects the module to stay silenced.

  Serializes module-level changes across async tests via a global lock.
  """
  @spec silence_for_test(module(), Logger.level()) :: :ok
  def silence_for_test(module, level \\ :error) do
    trans(fn ->
      bump_silence_count(module, +1)
      Logger.put_module_level(module, level)
    end)

    # Unique on_exit key per registration so concurrent tests each clean up.
    ExUnit.Callbacks.on_exit(make_ref(), fn ->
      trans(fn ->
        count = bump_silence_count(module, -1)

        if count <= 0 do
          Logger.delete_module_level(module)
        end
      end)
    end)

    :ok
  end

  @doc """
  Runs `fun` while holding the module-level lock so log assertions are not
  affected by other tests silencing the same module.

  Pass modules in `unsilence` to temporarily enable logging for them
  (e.g. another async test called `silence_for_test/2` on `Client`).

  Options:
  * `:unsilence` — modules whose level overrides are replaced for the duration
  * `:level` — level to apply while unsilenced (default `:all` so capture_log
    sees debug and warning even when the app logger level is `:warning`)
  """
  @spec with_logging((-> term()), keyword()) :: term()
  def with_logging(fun, opts \\ []) when is_function(fun, 0) do
    modules = Keyword.get(opts, :unsilence, [])
    enable_level = Keyword.get(opts, :level, :all)

    trans(fn ->
      previous = Map.new(modules, fn mod -> {mod, Logger.get_module_level(mod)} end)

      # Explicit permissive override (not delete_module_level/1): app log level
      # in test is :warning, so debug assertions need a module override, and a
      # bare delete leaves the module subject to other async silence_for_test/2
      # races once the lock is released.
      Enum.each(modules, &Logger.put_module_level(&1, enable_level))

      try do
        fun.()
      after
        Enum.each(previous, fn {mod, levels} -> restore_module_level(mod, levels) end)
      end
    end)
  end

  defp restore_module_level(mod, levels) when is_list(levels) do
    case List.keyfind(levels, mod, 0) do
      {^mod, level} -> Logger.put_module_level(mod, level)
      nil -> restore_after_unsilence(mod)
    end
  end

  defp restore_module_level(mod, level) when is_atom(level) do
    Logger.put_module_level(mod, level)
  end

  defp restore_module_level(mod, _other) do
    restore_after_unsilence(mod)
  end

  # If silencers are still active (refcount > 0), put the module back to :error
  # instead of deleting the override — otherwise concurrent PropertyReader tests
  # lose their silence and Client log tests may briefly see the wrong level on
  # the next with_logging snapshot.
  defp restore_after_unsilence(mod) do
    if silence_count(mod) > 0 do
      Logger.put_module_level(mod, :error)
    else
      Logger.delete_module_level(mod)
    end
  end

  defp bump_silence_count(module, delta) do
    counts = silence_counts()
    current = Map.get(counts, module, 0)
    next_count = max(current + delta, 0)
    :persistent_term.put(@counts_key, Map.put(counts, module, next_count))
    next_count
  end

  defp silence_count(module) do
    Map.get(silence_counts(), module, 0)
  end

  defp silence_counts() do
    :persistent_term.get(@counts_key, %{})
  rescue
    ArgumentError -> %{}
  end

  defp trans(fun) do
    :global.trans({@lock_key, node()}, fun, [node()], :infinity)
  end
end
