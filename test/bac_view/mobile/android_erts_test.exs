defmodule BacView.Mobile.AndroidErtsTest do
  use ExUnit.Case, async: true

  alias BacView.Mobile.AndroidErts

  describe "otp_version_major/1" do
    test "extracts major from full OTP_VERSION" do
      assert AndroidErts.otp_version_major("27.3.4.14") == "27"
      assert AndroidErts.otp_version_major("28.1.0") == "28"
      assert AndroidErts.otp_version_major("29.0") == "29"
    end

    test "accepts bare major" do
      assert AndroidErts.otp_version_major("27") == "27"
    end

    test "trims whitespace" do
      assert AndroidErts.otp_version_major("  27.2.4\n") == "27"
    end

    test "allows host patch skew vs zip (policy documentation)" do
      # Host 27.2.4 and Android zip 27.3.4.14 share major — prepare_release must allow this.
      host = "27.2.4"
      zip = "27.3.4.14"
      assert AndroidErts.otp_version_major(host) == AndroidErts.otp_version_major(zip)
      assert AndroidErts.otp_version_major(host) == "27"
    end

    test "detects major mismatch" do
      assert AndroidErts.otp_version_major("27.3.4.14") != AndroidErts.otp_version_major("28.0")
    end
  end
end
