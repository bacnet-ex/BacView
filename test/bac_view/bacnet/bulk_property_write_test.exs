defmodule BacView.BACnet.BulkPropertyWriteTest do
  use ExUnit.Case, async: false

  alias BACnet.Protocol.ObjectIdentifier
  alias BacView.BACnet.BulkPropertyWrite

  setup do
    previous_fun = Application.get_env(:bacview, :bulk_property_write_fun)
    previous_sync = Application.get_env(:bacview, :bulk_property_write_sync)

    on_exit(fn ->
      restore_env(:bulk_property_write_fun, previous_fun)
      restore_env(:bulk_property_write_sync, previous_sync)
    end)

    :ok
  end

  test "candidate properties are the shared writable scalars" do
    objects = [
      %{type: :analog_input, instance: 1},
      %{type: :binary_value, instance: 2}
    ]

    ids = BulkPropertyWrite.candidate_properties(objects)

    assert :present_value in ids
    assert :description in ids
    assert :out_of_service in ids
    assert :reliability in ids
    refute :cov_increment in ids
    refute :relinquish_default in ids
    refute :object_name in ids
    refute :priority_array in ids
    refute :status_flags in ids
  end

  test "candidate properties keep scalars shared by repeated types" do
    ids =
      BulkPropertyWrite.candidate_properties([
        %{type: :analog_input, instance: 1},
        %{type: :analog_input, instance: 2}
      ])

    assert :cov_increment in ids
    refute :relinquish_default in ids
  end

  test "types without a schema do not empty the shared list" do
    ids =
      BulkPropertyWrite.candidate_properties([
        %{type: :analog_input, instance: 1},
        %{type: :widget, instance: 9}
      ])

    assert :description in ids
    assert BulkPropertyWrite.candidate_properties([%{type: :widget, instance: 9}]) == []
    assert BulkPropertyWrite.candidate_properties([]) == []
  end

  test "parses scalars with the property type of each object" do
    analog = %{type: :analog_input, instance: 1}
    binary = %{type: :binary_value, instance: 2, active_text: "Ein", inactive_text: "Aus"}

    assert {:ok, "Halle"} = BulkPropertyWrite.parse_value(:description, " Halle ", analog)
    assert {:ok, true} = BulkPropertyWrite.parse_value(:out_of_service, "ja", analog)
    assert {:ok, false} = BulkPropertyWrite.parse_value(:out_of_service, "0", analog)

    assert {:error, :invalid_boolean} =
             BulkPropertyWrite.parse_value(:out_of_service, "maybe", analog)

    assert {:ok, 21.5} = BulkPropertyWrite.parse_value(:present_value, "21,5", analog)
    assert {:ok, 21.0} = BulkPropertyWrite.parse_value(:present_value, "21", analog)
    assert {:ok, nil} = BulkPropertyWrite.parse_value(:present_value, "null", analog)

    assert {:error, :invalid_number} =
             BulkPropertyWrite.parse_value(:present_value, "active", analog)

    assert {:ok, true} = BulkPropertyWrite.parse_value(:present_value, "Ein", binary)
    assert {:ok, true} = BulkPropertyWrite.parse_value(:present_value, "active", binary)
    assert {:ok, false} = BulkPropertyWrite.parse_value(:present_value, "Aus", binary)

    assert {:ok, :no_fault_detected} =
             BulkPropertyWrite.parse_value(:reliability, "no fault detected", analog)

    assert {:ok, :degrees_celsius} =
             BulkPropertyWrite.parse_value(:units, "degrees-celsius", %{
               type: :analog_value,
               instance: 1
             })

    assert {:ok, 8} =
             BulkPropertyWrite.parse_value(:priority_for_writing, "8", %{type: :loop, instance: 1})

    assert {:error, :out_of_range} =
             BulkPropertyWrite.parse_value(:priority_for_writing, "20", %{
               type: :loop,
               instance: 1
             })

    assert {:error, :invalid_number} =
             BulkPropertyWrite.parse_value(:notification_class, "-1", analog)

    assert {:error, :empty_value} = BulkPropertyWrite.parse_value(:description, "  ", analog)
  end

  test "run reports each write and passes priority only for commandable present values" do
    test_pid = self()

    Application.put_env(:bacview, :bulk_property_write_fun, fn device_id,
                                                               object_id,
                                                               property,
                                                               value,
                                                               opts ->
      send(test_pid, {:wrote, device_id, object_id, property, value, opts})
      if object_id.instance == 2, do: {:error, :timeout}, else: :ok
    end)

    jobs = [
      {%{type: :analog_value, instance: 1, commandable: true}, 1.5},
      {%{type: :analog_value, instance: 2, commandable: false}, 2.0}
    ]

    assert :ok = BulkPropertyWrite.run(self(), 7, :present_value, jobs, 4)

    assert_receive {:bulk_property_write_row, %{instance: 1, status: :writing}}

    assert_receive {:wrote, 7, %ObjectIdentifier{type: :analog_value, instance: 1},
                    :present_value, 1.5, opts}

    assert opts[:priority] == 4
    assert_receive {:bulk_property_write_row, %{instance: 1, status: :ok, reason: nil}}
    assert_receive {:wrote, 7, %ObjectIdentifier{instance: 2}, :present_value, 2.0, failed_opts}
    assert failed_opts[:priority] == nil

    assert_receive {:bulk_property_write_row, %{instance: 2, status: :error, reason: :timeout}}
    assert_receive {:bulk_property_write_done, %{ok: 1, failed: 1}}
  end

  test "a raising writer becomes an error row" do
    Application.put_env(:bacview, :bulk_property_write_fun, fn _device_id,
                                                               _object_id,
                                                               _property,
                                                               _value,
                                                               _opts ->
      raise "boom"
    end)

    jobs = [{%{type: :analog_input, instance: 1, commandable: false}, "x"}]

    assert :ok = BulkPropertyWrite.run(self(), 7, :description, jobs, 8)

    assert_receive {:bulk_property_write_row,
                    %{status: :error, reason: %RuntimeError{message: "boom"}}}

    assert_receive {:bulk_property_write_done, %{ok: 0, failed: 1}}
  end

  defp restore_env(key, nil), do: Application.delete_env(:bacview, key)
  defp restore_env(key, value), do: Application.put_env(:bacview, key, value)
end
