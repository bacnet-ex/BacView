defmodule BacView.Mobile.AndroidErts do
  @moduledoc """
  Helpers for Android OTP ERTS packaging.

  Host and Android ERTS trees must share the same OTP **major** (27, 28, 29).
  Exact `OTP_VERSION` patch matching is not required: the Android runtime rewrites
  `start_erl.data` and `ERTS_BIN` when merging the device ERTS zip.
  """

  @doc """
  Returns the OTP major from a full version string or release name.

      iex> BacView.Mobile.AndroidErts.otp_version_major("27.3.4.14")
      "27"
      iex> BacView.Mobile.AndroidErts.otp_version_major("28")
      "28"
  """
  @spec otp_version_major(String.t()) :: String.t()
  def otp_version_major(version) when is_binary(version) do
    trimmed = String.trim(version)

    case String.split(trimmed, ".", parts: 2) do
      [major | _rest] when major != "" -> major
      _other -> trimmed
    end
  end
end
