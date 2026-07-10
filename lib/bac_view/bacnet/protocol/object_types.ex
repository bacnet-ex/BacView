defmodule BacView.BACnet.Protocol.ObjectTypes do
  @moduledoc """
  Localized BACnet object type display names.
  """
  use Gettext, backend: BacViewWeb.Gettext

  @labels %{
    access_credential: {"Zugangsberechtigung", "Access Credential"},
    access_door: {"Zugangstür", "Access Door"},
    access_point: {"Zugangspunkt", "Access Point"},
    access_rights: {"Zugangsrechte", "Access Rights"},
    access_user: {"Zugangsbenutzer", "Access User"},
    access_zone: {"Zugangszone", "Access Zone"},
    accumulator: {"Akkumulator", "Accumulator"},
    alert_enrollment: {"Alarmanmeldung", "Alert Enrollment"},
    analog_input: {"Analogwert-Eingang", "Analog Input"},
    analog_output: {"Analogwert-Ausgang", "Analog Output"},
    analog_value: {"Analogwert", "Analog Value"},
    averaging: {"Mittelwert", "Averaging"},
    binary_input: {"Binäreingang", "Binary Input"},
    binary_lighting_output: {"Binärer Lichtausgang", "Binary Lighting Output"},
    binary_output: {"Binärausgang", "Binary Output"},
    binary_value: {"Binärwert", "Binary Value"},
    bitstring_value: {"Bitstring-Wert", "Bitstring Value"},
    calendar: {"Kalender", "Calendar"},
    channel: {"Kanal", "Channel"},
    character_string_value: {"Zeichenkettenwert", "Character String Value"},
    command: {"Befehl", "Command"},
    credential_data_input: {"Berechtigungsdaten-Eingang", "Credential Data Input"},
    date_pattern_value: {"Datums-Muster", "Date Pattern Value"},
    date_value: {"Datumswert", "Date Value"},
    datetime_pattern_value: {"Datumszeit-Muster", "DateTime Pattern Value"},
    datetime_value: {"Datumszeitwert", "DateTime Value"},
    device: {"Gerät", "Device"},
    elevator_group: {"Aufzugsgruppe", "Elevator Group"},
    escalator: {"Rolltreppe", "Escalator"},
    event_enrollment: {"Ereignisanmeldung", "Event Enrollment"},
    event_log: {"Ereignisprotokoll", "Event Log"},
    file: {"Datei", "File"},
    global_group: {"Globale Gruppe", "Global Group"},
    group: {"Gruppe", "Group"},
    integer_value: {"Ganzzahlwert", "Integer Value"},
    large_analog_value: {"Großer Analogwert", "Large Analog Value"},
    life_safety_point: {"Lebensrettungspunkt", "Life Safety Point"},
    life_safety_zone: {"Lebensrettungszone", "Life Safety Zone"},
    lift: {"Aufzug", "Lift"},
    lighting_output: {"Lichtausgang", "Lighting Output"},
    load_control: {"Laststeuerung", "Load Control"},
    loop: {"Regelkreis", "Loop"},
    multi_state_input: {"Mehrstufiger Eingang", "Multi-state Input"},
    multi_state_output: {"Mehrstufiger Ausgang", "Multi-state Output"},
    multi_state_value: {"Mehrstufiger Wert", "Multi-state Value"},
    network_port: {"Netzwerkport", "Network Port"},
    network_security: {"Netzwerksicherheit", "Network Security"},
    notification_class: {"Meldungsklasse", "Notification Class"},
    notification_forwarder: {"Meldungsweiterleitung", "Notification Forwarder"},
    octet_string_value: {"Oktett-String-Wert", "Octet String Value"},
    positive_integer_value: {"Positive Ganzzahl", "Positive Integer Value"},
    program: {"Programm", "Program"},
    pulse_converter: {"Impulsumformer", "Pulse Converter"},
    schedule: {"Zeitplan", "Schedule"},
    structured_view: {"Strukturansicht", "Structured View"},
    time_pattern_value: {"Zeit-Muster", "Time Pattern Value"},
    time_value: {"Zeitwert", "Time Value"},
    timer: {"Timer", "Timer"},
    trend_log: {"Trendprotokoll", "Trend Log"},
    trend_log_multiple: {"Mehrfach-Trendprotokoll", "Trend Log Multiple"}
  }

  @spec label(atom() | integer()) :: String.t()
  def label(type) when is_atom(type) do
    case localized_pair(type) do
      {de, en} ->
        case Gettext.get_locale(BacViewWeb.Gettext) do
          "en" -> "#{en} (#{type})"
          _type -> "#{de} (#{en})"
        end

      nil ->
        humanized = humanize_atom(type)
        "#{humanized} (#{type})"
    end
  end

  def label(type) when is_integer(type), do: Integer.to_string(type)

  @doc """
  Compact localized object type name without the BACnet type atom suffix.
  """
  @spec short_label(atom() | integer()) :: String.t()
  def short_label(type) when is_atom(type) do
    case localized_pair(type) do
      {de, en} ->
        case Gettext.get_locale(BacViewWeb.Gettext) do
          "en" -> en
          _type -> de
        end

      nil ->
        humanize_atom(type)
    end
  end

  def short_label(type) when is_integer(type), do: Integer.to_string(type)

  defp localized_pair(type), do: Map.get(@labels, type)

  defp humanize_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
