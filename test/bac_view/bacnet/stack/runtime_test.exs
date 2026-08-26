defmodule BacView.BACnet.Stack.RuntimeTest do
  use ExUnit.Case, async: true

  alias BacView.BACnet.Stack.Runtime
  alias BacView.Settings

  test "client opts use APDU timeout and retries" do
    settings = %{Settings.defaults() | apdu_timeout: 5_000, apdu_retries: 7}

    opts = Runtime.client_opts(settings)
    assert opts[:apdu_timeout] == 5_000
    assert opts[:apdu_retries] == 7
  end

  test "segmentator opts use segments timeout and APDU retries" do
    settings = %{
      Settings.defaults()
      | apdu_retries: 7,
        apdu_segments_timeout: 4_000
    }

    opts = Runtime.segmentator_opts(settings)
    assert opts[:apdu_timeout] == 4_000
    assert opts[:apdu_retries] == 7
  end

  test "segments store opts use segments timeout and max segments without retries" do
    settings = %{
      Settings.defaults()
      | apdu_retries: 7,
        apdu_segments_timeout: 4_000,
        max_segments: 16
    }

    opts = Runtime.segments_store_opts(settings)
    assert opts[:apdu_timeout] == 4_000
    assert opts[:max_segments] == 16
    refute Keyword.has_key?(opts, :apdu_retries)
  end

  test "apply_apdu_settings is a no-op when the stack is not running" do
    assert :ok = Runtime.apply_apdu_settings(Settings.defaults())
  end
end
