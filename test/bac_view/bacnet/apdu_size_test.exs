defmodule BacView.BACnet.ApduSizeTest do
  use ExUnit.Case, async: false

  alias BacView.BACnet.ApduSize
  alias BacView.Settings

  setup do
    previous = Settings.get().max_apdu_length
    on_exit(fn -> _ = Settings.update(max_apdu_length: previous) end)
    :ok
  end

  describe "normalize/1" do
    test "maps to next smaller or equal constant" do
      assert ApduSize.normalize(1476) == {:ok, 1476}
      assert ApduSize.normalize(1000) == {:ok, 480}
      assert ApduSize.normalize(481) == {:ok, 480}
      assert ApduSize.normalize(480) == {:ok, 480}
      assert ApduSize.normalize(50) == {:ok, 50}
    end

    test "clamps then snaps out-of-range positive integers" do
      assert ApduSize.normalize(30) == {:ok, 50}
      assert ApduSize.normalize(2000) == {:ok, 1476}
    end

    test "rejects non-positive / non-integer" do
      assert ApduSize.normalize(0) == {:error, :invalid_apdu_size}
      assert ApduSize.normalize(-1) == {:error, :invalid_apdu_size}
      assert ApduSize.normalize("480") == {:error, :invalid_apdu_size}
    end
  end

  describe "effective_raw/1 and effective/1" do
    test "raw is min of local setting and remote; effective snaps for encode" do
      assert {:ok, _} = Settings.update(max_apdu_length: 1476)

      assert ApduSize.effective_raw(1000) == 1000
      assert ApduSize.effective(1000) == 480

      assert ApduSize.effective_raw(480) == 480
      assert ApduSize.effective(480) == 480

      assert ApduSize.effective_raw(nil) == 1476
      assert ApduSize.effective(nil) == 1476
    end

    test "respects reduced local setting as raw cap" do
      assert {:ok, _} = Settings.update(max_apdu_length: 1000)

      assert ApduSize.local_raw() == 1000
      assert ApduSize.local() == 480
      assert ApduSize.effective_raw(1476) == 1000
      assert ApduSize.effective(1476) == 480
    end
  end

  describe "to_opts/1" do
    test "splits snapped max_apdu from raw max_apdu_length" do
      assert {:ok, _} = Settings.update(max_apdu_length: 1476)

      opts = ApduSize.to_opts(1000)
      assert opts[:max_apdu] == 480
      assert opts[:max_apdu_length] == 1000

      opts_equal = ApduSize.to_opts(480)
      assert opts_equal[:max_apdu] == 480
      assert opts_equal[:max_apdu_length] == 480
    end
  end
end
