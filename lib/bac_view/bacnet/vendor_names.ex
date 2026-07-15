defmodule BacView.BACnet.VendorNames do
  @moduledoc false

  alias BACnet.Protocol.ObjectTypes.Device

  @spec names() :: %{optional(non_neg_integer()) => String.t()}
  def names() do
    Device.get_vendor_ids()
  end

  @spec label(map(), non_neg_integer() | nil) :: String.t()
  def label(_names, nil), do: "-"

  def label(names, vendor_id) when is_integer(vendor_id) do
    case Map.get(names, vendor_id, "") do
      "" -> Integer.to_string(vendor_id)
      name -> "#{vendor_id} · #{name}"
    end
  end
end
