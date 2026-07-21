defmodule BacView.BACnet.ApduSize do
  @moduledoc """
  Local/remote max APDU handling for bacstack request opts.

  * **Settings** store a raw length in **50..1476**.
  * **`:max_apdu`** (ConfirmedServiceRequest encode) must be a BACnet constant
    (`50 | 128 | 206 | 480 | 1024 | 1476`) — snap to the largest constant **≤**
    the effective raw size.
  * **`:max_apdu_length`** (`Client.send` / segmentation) uses the **raw**
    effective size `min(local, remote)` without snapping. The peer can accept
    any length up to its announced max; this value is only for buffer math.
  """

  alias BacView.Settings

  @constants [50, 128, 206, 480, 1024, 1476]
  @min_apdu 50
  @max_apdu 1476

  @doc "Defined BACnet max APDU length constants (ascending)."
  @spec constants() :: [pos_integer()]
  def constants(), do: @constants

  @doc """
  Largest BACnet APDU constant ≤ `value` (for ConfirmedServiceRequest).

  Accepts any positive integer; values below 50 map to 50, above 1476 to 1476
  before selecting the constant.
  """
  @spec normalize(term()) :: {:ok, pos_integer()} | {:error, :invalid_apdu_size}
  def normalize(value) when is_integer(value) and value > 0 do
    clamped = value |> max(@min_apdu) |> min(@max_apdu)
    candidates = Enum.filter(@constants, &(&1 <= clamped))

    case List.last(candidates) do
      nil -> {:error, :invalid_apdu_size}
      constant -> {:ok, constant}
    end
  end

  def normalize(_value), do: {:error, :invalid_apdu_size}

  @doc "Like `normalize/1` but raises on invalid input."
  @spec normalize!(term()) :: pos_integer()
  def normalize!(value) do
    case normalize(value) do
      {:ok, constant} -> constant
      {:error, reason} -> raise ArgumentError, "invalid max APDU size: #{inspect(reason)}"
    end
  end

  @doc """
  Local max APDU from settings as a raw octet count (50..1476), not snapped.
  """
  @spec local_raw() :: pos_integer()
  def local_raw() do
    case Settings.max_apdu_length() do
      value when is_integer(value) and value in @min_apdu..@max_apdu -> value
      _invalid -> @max_apdu
    end
  end

  @doc """
  Local max APDU snapped to a BACnet constant (for UI / ConfirmedServiceRequest alone).
  """
  @spec local() :: pos_integer()
  def local(), do: normalize!(local_raw())

  @doc """
  Raw effective size for segmentation / `Client.send`: `min(local_raw, remote)`
  when remote is known, otherwise `local_raw`. Not snapped to constants.
  """
  @spec effective_raw(pos_integer() | nil | map()) :: pos_integer()
  def effective_raw(nil), do: local_raw()

  def effective_raw(remote) when is_integer(remote) and remote > 0 do
    min(local_raw(), remote)
  end

  def effective_raw(%{max_apdu: max_apdu}) when is_integer(max_apdu) and max_apdu > 0 do
    effective_raw(max_apdu)
  end

  def effective_raw(_other), do: local_raw()

  @doc """
  Effective size for ConfirmedServiceRequest: `normalize(effective_raw(remote))`.
  """
  @spec effective(pos_integer() | nil | map()) :: pos_integer()
  def effective(remote \\ nil) do
    normalize!(effective_raw(remote))
  end

  @doc """
  Keyword opts for bacstack:

  * `:max_apdu` — snapped constant for service encode
  * `:max_apdu_length` — raw effective length for `Client.send` / segments
  """
  @spec to_opts(pos_integer() | nil | map()) :: keyword()
  def to_opts(remote \\ nil) do
    raw = effective_raw(remote)

    [
      max_apdu: normalize!(raw),
      max_apdu_length: raw
    ]
  end
end
