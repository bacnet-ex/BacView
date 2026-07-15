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
  """
  @spec with_logging((-> term())) :: term()
  def with_logging(fun) when is_function(fun, 0) do
    trans(fun)
  end

  defp trans(fun) do
    :global.trans(@lock, fun, [node()], :infinity)
  end
end
