defmodule BacView.Test.SilenceLogger do
  @moduledoc false

  @lock {:bacview_logger_module_level_lock, node()}

  @doc """
  Raises the log level for `module` for the current test and restores it on exit.

  Serializes module-level changes across async tests via a global lock.
  """
  @spec silence_for_test(module(), Logger.level()) :: :ok
  def silence_for_test(module, level \\ :error) do
    trans(fn ->
      Logger.put_module_level(module, level)
    end)

    ExUnit.Callbacks.on_exit({:silence_logger, module}, fn ->
      trans(fn ->
        Logger.delete_module_level(module)
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
  * `:level` — level to apply while unsilenced (default `:debug`)
  """
  @spec with_logging((-> term()), keyword()) :: term()
  def with_logging(fun, opts \\ []) when is_function(fun, 0) do
    modules = Keyword.get(opts, :unsilence, [])
    enable_level = Keyword.get(opts, :level, :debug)

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
      nil -> Logger.delete_module_level(mod)
    end
  end

  defp restore_module_level(mod, level) when is_atom(level) do
    Logger.put_module_level(mod, level)
  end

  defp restore_module_level(mod, _other) do
    Logger.delete_module_level(mod)
  end

  defp trans(fun) do
    :global.trans(@lock, fun, [node()], :infinity)
  end
end
