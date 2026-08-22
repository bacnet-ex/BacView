defmodule BacViewWeb.LiveMailboxTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.LiveMailbox

  test "drain_repeated drops queued copies and leaves other messages" do
    send(self(), :cov_updated)
    send(self(), :cov_updated)
    send(self(), {:keep, :me})
    send(self(), :cov_updated)

    assert :ok = LiveMailbox.drain_repeated(:cov_updated)

    refute_received :cov_updated
    assert_received {:keep, :me}
  end
end
