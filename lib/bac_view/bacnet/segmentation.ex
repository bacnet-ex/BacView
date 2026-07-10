defmodule BacView.BACnet.Segmentation do
  @moduledoc false

  alias BACnet.Protocol.APDU

  @fallback_error_atoms [
    :segmentation_not_supported,
    :buffer_overflow,
    :abort_buffer_overflow,
    :reject_buffer_overflow
  ]

  @fallback_abort_reasons [:segmentation_not_supported, :buffer_overflow]
  @fallback_abort_codes [4, 1]

  @fallback_reject_reasons [:buffer_overflow]
  @fallback_reject_codes [1]

  @spec fallback_error?(term()) :: boolean()
  def fallback_error?({:error, reason}), do: fallback_reason?(reason)
  def fallback_error?(_error), do: false

  defp fallback_reason?(reason) when reason in @fallback_error_atoms, do: true

  defp fallback_reason?({reason, _oid}) when reason in @fallback_error_atoms, do: true

  defp fallback_reason?({:bacnet_abort, %APDU.Abort{reason: reason}}),
    do: abort_fallback_reason?(reason)

  defp fallback_reason?({{:bacnet_abort, %APDU.Abort{reason: reason}}, _oid}),
    do: abort_fallback_reason?(reason)

  defp fallback_reason?({:bacnet_reject, %APDU.Reject{reason: reason}}),
    do: reject_fallback_reason?(reason)

  defp fallback_reason?({{:bacnet_reject, %APDU.Reject{reason: reason}}, _oid}),
    do: reject_fallback_reason?(reason)

  defp fallback_reason?(_reason), do: false

  defp abort_fallback_reason?(reason)
       when reason in @fallback_abort_reasons or reason in @fallback_abort_codes,
       do: true

  defp abort_fallback_reason?(_reason), do: false

  defp reject_fallback_reason?(reason)
       when reason in @fallback_reject_reasons or reason in @fallback_reject_codes,
       do: true

  defp reject_fallback_reason?(_reason), do: false
end
