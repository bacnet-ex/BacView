defmodule BacView.BACnet.Protocol.ErrorMessage do
  @moduledoc """
  User-facing BACnet and application error messages.

  Converts low-level APDU errors, rejects, and aborts into short messages for
  flash toasts. Use `detail/1` when logging the full error for developers.
  """

  use Gettext, backend: BacViewWeb.Gettext

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.BACnetError
  alias BACnet.Protocol.Constants

  @type action ::
          :cov_subscribe
          | :cov_unsubscribe
          | :load_properties
          | :refresh_properties
          | :write_property
          | :read_back_property
          | :load_device
          | :fetch_events
          | :export_events
          | :export_ede
          | :notification_class_recipient
          | :bbmd_register
          | :stack_restart
          | :network_scan
          | :device_communication_control
          | :reinitialize_device
          | :time_synchronization
          | :atomic_read_file
          | :atomic_write_file
          | :generic

  @doc """
  Returns a short, user-facing message for a failed action.
  """
  @spec for_action(action(), term()) :: String.t()
  def for_action(action, reason) do
    detail = format_reason(reason)

    case action do
      a when a in [:cov_subscribe, :cov_unsubscribe, :load_properties, :refresh_properties] ->
        property_action_message(a, detail)

      a
      when a in [
             :write_property,
             :read_back_property,
             :load_device,
             :fetch_events,
             :export_events,
             :export_ede
           ] ->
        data_action_message(a, detail)

      a
      when a in [
             :notification_class_recipient,
             :bbmd_register,
             :stack_restart,
             :network_scan,
             :device_communication_control,
             :reinitialize_device,
             :time_synchronization,
             :atomic_read_file,
             :atomic_write_file
           ] ->
        service_action_message(a, detail)

      :generic ->
        detail
    end
  end

  defp property_action_message(:cov_subscribe, detail),
    do: gettext("COV-Abonnement fehlgeschlagen: %{detail}", detail: detail)

  defp property_action_message(:cov_unsubscribe, detail),
    do: gettext("COV-Abonnement kündigen fehlgeschlagen: %{detail}", detail: detail)

  defp property_action_message(:load_properties, detail),
    do: gettext("Eigenschaften laden fehlgeschlagen: %{detail}", detail: detail)

  defp property_action_message(:refresh_properties, detail),
    do: gettext("Eigenschaften aktualisieren fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:write_property, detail),
    do: gettext("Schreiben fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:read_back_property, detail),
    do: gettext("Schreiben OK, aber Rücklesen fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:load_device, detail),
    do: gettext("Gerät laden fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:fetch_events, detail),
    do: gettext("Ereignisse abrufen fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:export_events, detail),
    do: gettext("Ereignis-Export fehlgeschlagen: %{detail}", detail: detail)

  defp data_action_message(:export_ede, detail),
    do: gettext("EDE-Export fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:notification_class_recipient, detail),
    do: gettext("Meldungsklassen-Empfängerliste fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:bbmd_register, detail),
    do: gettext("BBMD-Registrierung fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:stack_restart, detail),
    do: gettext("Stack-Neustart fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:network_scan, detail),
    do: gettext("Scan fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:device_communication_control, detail),
    do: gettext("Gerätekommunikation fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:reinitialize_device, detail),
    do: gettext("Neuinitialisierung fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:time_synchronization, detail),
    do: gettext("Zeitsynchronisation fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:atomic_read_file, detail),
    do: gettext("Datei lesen fehlgeschlagen: %{detail}", detail: detail)

  defp service_action_message(:atomic_write_file, detail),
    do: gettext("Datei schreiben fehlgeschlagen: %{detail}", detail: detail)

  @doc """
  Returns a developer-oriented representation for console or server logs.
  """
  @spec detail(term()) :: String.t()
  def detail(reason) do
    inspect(reason, pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  @doc """
  Formats any supported error reason for display.
  """
  @spec format_reason(term()) :: String.t()
  def format_reason({:bacnet_error, %APDU.Error{} = error}), do: format_apdu_error(error)
  def format_reason({:bacnet_reject, %APDU.Reject{} = reject}), do: format_reject(reject)
  def format_reason({:bacnet_abort, %APDU.Abort{} = abort}), do: format_abort(abort)
  def format_reason(%APDU.Error{} = error), do: format_apdu_error(error)
  def format_reason(%APDU.Reject{} = reject), do: format_reject(reject)
  def format_reason(%APDU.Abort{} = abort), do: format_abort(abort)
  def format_reason(%BACnetError{} = error), do: format_bacnet_error(error)
  def format_reason({:error, reason}), do: format_reason(reason)

  def format_reason({:value_failed_property_validation, property}),
    do:
      gettext("Eigenschaftswert entspricht nicht der BACnet-Spezifikation (%{property}).",
        property: label(property)
      )

  def format_reason({:invalid_property_type, property}),
    do:
      gettext("Eigenschaftswert hat einen ungültigen BACnet-Datentyp (%{property}).",
        property: label(property)
      )

  def format_reason(:device_not_found), do: gettext("Gerät nicht gefunden.")
  def format_reason(:device_not_loaded), do: gettext("Gerätedaten sind noch nicht geladen.")

  def format_reason(:enrollment_failed),
    do: gettext("Eintrag in die Empfängerliste fehlgeschlagen.")

  def format_reason(:invalid_datetime_range),
    do: gettext("Ungültiger Zeitraum. Bitte Start- und Endzeit prüfen.")

  def format_reason(:timeout), do: gettext("Zeitüberschreitung bei der Gerätekommunikation.")
  def format_reason(:noproc), do: gettext("Keine Verbindung zum BACnet-Stack.")

  def format_reason(:stack_not_started),
    do: gettext("BACnet-Stack ist nicht gestartet.")

  def format_reason(:bacnet_unavailable),
    do: gettext("BACnet-Stack ist nicht gestartet.")

  def format_reason(:no_network_interface),
    do: gettext("Keine Netzwerkschnittstelle für BACnet/IP verfügbar.")

  def format_reason(:no_serial_port),
    do: gettext("Kein serieller Port für BACnet MS/TP verfügbar.")

  def format_reason(:no_serial_ports),
    do: gettext("Keine seriellen Ports gefunden.")

  def format_reason({:no_serial_ports, _child}),
    do: format_reason(:no_serial_ports)

  def format_reason({:transport_not_available, transport}),
    do: gettext("Transport %{transport} ist nicht verfügbar.", transport: label(transport))

  def format_reason({:shutdown, reason}), do: format_reason(reason)

  def format_reason({:runtime_down, reason}), do: format_reason(reason)

  def format_reason({:failed_to_start_child, _module, reason}), do: format_reason(reason)

  def format_reason({{:shutdown, {:failed_to_start_child, _module, reason}}, _child}),
    do: format_reason(reason)

  def format_reason(:invalid_project_name),
    do: gettext("Projektname fehlt oder ist ungültig.")

  def format_reason(:invalid_version),
    do: gettext("Version muss semantisch sein (z. B. 1.0.0).")

  def format_reason(:no_objects),
    do: gettext("Keine exportierbaren Objekte geladen.")

  def format_reason(:no_object_types_selected),
    do: gettext("Mindestens ein Objekttyp muss ausgewählt sein.")

  def format_reason(:eacces),
    do: gettext("Zugriff auf den seriellen Port verweigert (Berechtigung fehlt).")

  def format_reason(:eaddrinuse),
    do:
      gettext(
        "UDP-Port ist bereits belegt (eaddrinuse). Möglicherweise läuft bereits eine andere BACnet-Anwendung auf diesem Port."
      )

  def format_reason(:eaddrnotavail),
    do: gettext("Netzwerkadresse ist nicht verfügbar (eaddrnotavail).")

  def format_reason(:enoent), do: gettext("Serieller Port nicht gefunden.")
  def format_reason(:ebusy), do: gettext("Serieller Port ist belegt.")
  def format_reason(:eperm), do: gettext("Keine Berechtigung für den seriellen Port.")

  def format_reason({:bbmd_reregister_failed, reason}),
    do:
      gettext("Stack neu gestartet, aber BBMD-Registrierung fehlgeschlagen: %{detail}",
        detail: format_reason(reason)
      )

  def format_reason(reason) when is_atom(reason) do
    error_code_message(reason) || format_unknown_atom(reason)
  end

  def format_reason(reason) when is_binary(reason), do: reason

  def format_reason({%{__exception__: true} = exception, _stacktrace}),
    do: format_exception_message(exception)

  def format_reason(%{__exception__: true} = exception),
    do: format_exception_message(exception)

  def format_reason(_reason),
    do: gettext("Ein unerwarteter Fehler ist aufgetreten.")

  defp format_exception_message(%RuntimeError{message: message}),
    do: format_runtime_error_message(message)

  defp format_exception_message(exception), do: Exception.message(exception)

  defp format_runtime_error_message("Unable to find ethernet interface " <> rest) do
    case Regex.run(~r/\(with broadcast flag\) called (.+)$/, rest) do
      [_match, interface] ->
        gettext("Netzwerkschnittstelle nicht gefunden: %{interface}", interface: interface)

      _no_match ->
        gettext("Netzwerkschnittstelle nicht gefunden.")
    end
  end

  defp format_runtime_error_message("Unable to discover local IPv4 address"),
    do: format_reason(:no_network_interface)

  defp format_runtime_error_message(
         "Unable to enumerate ethernet interfaces, error: " <> _detail
       ),
       do: gettext("Netzwerkschnittstellen konnten nicht ermittelt werden.")

  defp format_runtime_error_message(message) when is_binary(message), do: message

  defp format_unknown_atom(reason),
    do: gettext("Systemfehler: %{reason}", reason: label(reason))

  defp format_apdu_error(%APDU.Error{code: code, class: class}) do
    case error_code_message(code) do
      nil -> combine_class_and_code(class, code)
      message -> message
    end
  end

  defp format_bacnet_error(%BACnetError{code: code, class: class}) do
    case error_code_message(code) do
      nil -> combine_class_and_code(class, code)
      message -> message
    end
  end

  defp format_reject(%APDU.Reject{reason: reason}) do
    reject_reason_message(reason) ||
      gettext("Kommunikationsfehler (%{reason})", reason: label(reason))
  end

  defp format_abort(%APDU.Abort{reason: reason}) do
    abort_reason_message(reason) ||
      gettext("Verbindung abgebrochen (%{reason})", reason: label(reason))
  end

  defp combine_class_and_code(class, code) do
    gettext("%{class}: %{code}",
      class: error_class_label(class),
      code: label(code)
    )
  end

  defp error_class_label(class) do
    case error_class_message(class) do
      nil -> label(class)
      message -> message
    end
  end

  defp error_class_message(:device), do: gettext("Gerätefehler")
  defp error_class_message(:object), do: gettext("Objektfehler")
  defp error_class_message(:property), do: gettext("Eigenschaftsfehler")
  defp error_class_message(:resources), do: gettext("Ressourcenfehler")
  defp error_class_message(:security), do: gettext("Sicherheitsfehler")
  defp error_class_message(:services), do: gettext("Dienstfehler")
  defp error_class_message(:communication), do: gettext("Kommunikationsfehler")
  defp error_class_message(_error_class_message), do: nil

  defp error_code_message(:optional_functionality_not_supported),
    do: gettext("Das Gerät unterstützt diese Funktion nicht.")

  defp error_code_message(:cov_subscription_failed),
    do: gettext("Das COV-Abonnement konnte nicht eingerichtet werden.")

  defp error_code_message(:not_cov_property),
    do: gettext("Diese Eigenschaft unterstützt keine COV-Benachrichtigungen.")

  defp error_code_message(:unknown_subscription),
    do: gettext("Kein aktives COV-Abonnement gefunden.")

  defp error_code_message(:service_request_denied),
    do: gettext("Das Gerät hat die Anfrage abgelehnt.")

  defp error_code_message(:unknown_object),
    do: gettext("Das Objekt ist dem Gerät nicht bekannt.")

  defp error_code_message(:unknown_property),
    do: gettext("Die Eigenschaft ist dem Gerät nicht bekannt.")

  defp error_code_message(:read_access_denied),
    do: gettext("Lesezugriff verweigert.")

  defp error_code_message(:write_access_denied),
    do: gettext("Schreibzugriff verweigert.")

  defp error_code_message(:device_busy),
    do: gettext("Das Gerät ist beschäftigt. Bitte später erneut versuchen.")

  defp error_code_message(:timeout),
    do: gettext("Zeitüberschreitung bei der Gerätekommunikation.")

  defp error_code_message(:network_down),
    do: gettext("Netzwerkverbindung zum Gerät nicht verfügbar.")

  defp error_code_message(:inconsistent_parameters),
    do: gettext("Ungültige Anfrageparameter.")

  defp error_code_message(:value_out_of_range),
    do: gettext("Der Wert liegt ausserhalb des erlaubten Bereichs.")

  defp error_code_message(:parameter_out_of_range),
    do: gettext("Ein Parameter liegt ausserhalb des erlaubten Bereichs.")

  defp error_code_message(code) when is_atom(code) do
    if Constants.has_by_name(:error_code, code) do
      gettext("Gerätefehler: %{code}", code: label(code))
    else
      nil
    end
  end

  defp error_code_message(code) when is_integer(code),
    do: gettext("Gerätefehler (Code %{code})", code: code)

  defp error_code_message(_optional_functionality_not_supported), do: nil

  defp reject_reason_message(:reject_unrecognized_service),
    do: gettext("Das Gerät unterstützt diesen Dienst nicht.")

  defp reject_reason_message(:reject_buffer_overflow),
    do: gettext("Die Anfrage war für das Gerät zu gross.")

  defp reject_reason_message(:reject_missing_required_parameter),
    do: gettext("Der Anfrage fehlen erforderliche Parameter.")

  defp reject_reason_message(:reject_inconsistent_parameters),
    do: gettext("Die Anfrage enthält ungültige Parameter.")

  defp reject_reason_message(:reject_invalid_tag),
    do: gettext("Die Anfrage enthält ungültige BACnet-Daten.")

  defp reject_reason_message(_reject_unrecognized_service), do: nil

  defp abort_reason_message(:tsm_timeout),
    do: gettext("Zeitüberschreitung bei der Gerätekommunikation.")

  defp abort_reason_message(:application_exceeded_reply_time),
    do: gettext("Das Gerät hat nicht rechtzeitig geantwortet.")

  defp abort_reason_message(:segmentation_not_supported),
    do: gettext("Das Gerät unterstützt keine Segmentierung.")

  defp abort_reason_message(:buffer_overflow),
    do: gettext("Die Anfrage war für das Gerät zu gross.")

  defp abort_reason_message(:out_of_resources),
    do: gettext("Das Gerät hat nicht genügend Ressourcen.")

  defp abort_reason_message(_tsm_timeout), do: nil

  defp label(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp label(value), do: to_string(value)
end
