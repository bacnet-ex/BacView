defmodule BacView.PlatformTest do
  use ExUnit.Case, async: true

  alias BacView.Platform

  test "defaults to web mode in test" do
    assert Platform.web?()
    refute Platform.desktop?()
    assert Platform.mstp_enabled?()
  end
end
