defmodule BacView.BACnet.VendorNamesTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.VendorNames

  test "label/2 formats vendor id with known name" do
    names = VendorNames.names()

    case Enum.find(names, fn {_id, name} -> name != "" end) do
      {id, name} ->
        assert VendorNames.label(names, id) == "#{id} · #{name}"

      nil ->
        assert VendorNames.label(%{42 => "Example Vendor"}, 42) == "42 · Example Vendor"
    end
  end

  test "label/2 falls back to id only when name is unknown" do
    assert VendorNames.label(%{}, 999_999) == "999999"
    assert VendorNames.label(%{}, nil) == "-"
  end
end
