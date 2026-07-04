defmodule BacView.BACnet.StackLifecycleTest do
  use ExUnit.Case, async: false

  alias BacView.BACnet.StackLifecycle

  test "restart returns error when stack child is not supervised" do
    stack_supervised? =
      BacView.Supervisor
      |> Supervisor.which_children()
      |> Enum.any?(fn {id, _, _, _} -> id == BacView.BACnet.Stack end)

    if stack_supervised? do
      :ok
    else
      assert {:error, :stack_not_started} = StackLifecycle.restart()
    end
  end
end
