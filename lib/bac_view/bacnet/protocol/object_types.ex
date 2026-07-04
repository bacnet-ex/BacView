defmodule BacView.BACnet.Protocol.ObjectTypes do
  @moduledoc """
  Localized BACnet object type display names.
  """
  use Gettext, backend: BacViewWeb.Gettext

  @labels %{
    analog_input: {"Analogwert-Eingang", "Analog Input"},
    analog_output: {"Analogwert-Ausgang", "Analog Output"},
    analog_value: {"Analogwert", "Analog Value"},
    binary_input: {"Binäreingang", "Binary Input"},
    binary_output: {"Binärausgang", "Binary Output"},
    binary_value: {"Binärwert", "Binary Value"},
    device: {"Gerät", "Device"},
    structured_view: {"Strukturansicht", "Structured View"},
    trend_log: {"Trendprotokoll", "Trend Log"},
    notification_class: {"Meldungsklasse", "Notification Class"}
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
        Atom.to_string(type)
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
        Atom.to_string(type)
    end
  end

  def short_label(type) when is_integer(type), do: Integer.to_string(type)

  defp localized_pair(type), do: Map.get(@labels, type)
end
