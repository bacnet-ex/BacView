defmodule BacView.BACnet.ClientResultTest do
  use ExUnit.Case, async: true

  alias BACnet.Protocol.APDU
  alias BacView.BACnet.ClientResult

  test "passes through :ok and {:ok, value}" do
    assert ClientResult.normalize(:ok) == :ok
    assert ClientResult.normalize({:ok, :payload}) == {:ok, :payload}
  end

  test "does not double-wrap already tagged errors" do
    assert ClientResult.normalize({:error, :timeout}) == {:error, :timeout}
  end

  test "normalizes APDU error/reject/abort tuples" do
    error = %APDU.Error{
      invoke_id: 1,
      service: :write_property,
      class: :property,
      code: :write_access_denied,
      payload: []
    }

    reject = %APDU.Reject{invoke_id: 1, reason: :unrecognized_service}
    abort = %APDU.Abort{sent_by_server: true, invoke_id: 1, reason: :buffer_overflow}

    assert ClientResult.normalize({:error, error}) == {:error, {:bacnet_error, error}}
    assert ClientResult.normalize({:error, reject}) == {:error, {:bacnet_reject, reject}}
    assert ClientResult.normalize({:error, abort}) == {:error, {:bacnet_abort, abort}}
  end

  test "wraps bare APDU values once (write/COV helper shapes)" do
    error = %APDU.Error{
      invoke_id: 2,
      service: :write_property,
      class: :property,
      code: :unknown_property,
      payload: []
    }

    assert ClientResult.normalize(error) == {:error, {:bacnet_error, error}}
  end

  test "write-shaped ClientHelper errors stay single-wrapped" do
    # ClientHelper returns {:error, reason}; normalize must not nest to
    # {:error, {:error, reason}}.
    assert ClientResult.normalize({:error, :apdu_timeout}) == {:error, :apdu_timeout}
  end
end
