defmodule BacView.BACnet.DeviceServices do
  @moduledoc """
  High-level BACnet device service execution (DCC, Reinitialize, Time Sync).
  """

  alias BACnet.Protocol.Constants
  alias BacView.BACnet.Client
  alias BacView.BACnet.Discovery

  @type result :: :ok | {:error, term()}

  @doc "Returns the BACnet destination address for a discovered device."
  @spec device_address(integer()) :: {:ok, term()} | {:error, :device_not_found}
  def device_address(device_id) do
    case Discovery.get_device(device_id) do
      {:ok, %{address: address}} -> {:ok, address}
      :error -> {:error, :device_not_found}
    end
  end

  @doc "Executes Device Communication Control with parsed form parameters."
  @spec device_communication_control(integer(), map()) :: result
  def device_communication_control(device_id, params) when is_map(params) do
    with {:ok, address} <- device_address(device_id),
         {:ok, state} <- parse_enable_disable(Map.get(params, "state", "disable")),
         {:ok, time_duration} <- parse_time_duration(Map.get(params, "time_duration", "")),
         password <- parse_password(Map.get(params, "password", "")) do
      Client.device_communication_control(address, state, time_duration, password)
    end
  end

  @doc "Executes Reinitialize Device with parsed form parameters."
  @spec reinitialize_device(integer(), map()) :: result
  def reinitialize_device(device_id, params) when is_map(params) do
    with {:ok, address} <- device_address(device_id),
         {:ok, state} <-
           parse_reinitialized_state(Map.get(params, "reinitialized_state", "warmstart")),
         password <- parse_password(Map.get(params, "password", "")) do
      Client.reinitialize_device(address, state, password)
    end
  end

  @doc "Executes Time Synchronization with parsed form parameters."
  @spec send_time_synchronization(integer(), map()) :: result
  def send_time_synchronization(device_id, params) when is_map(params) do
    with {:ok, address} <- device_address(device_id) do
      utc = Map.get(params, "time_mode", "local") == "utc"

      Client.send_time_synchronization(address, utc: utc)
    end
  end

  @spec parse_enable_disable(String.t()) :: {:ok, Constants.enable_disable()} | {:error, term()}
  def parse_enable_disable("enable"), do: {:ok, :enable}
  def parse_enable_disable("disable"), do: {:ok, :disable}
  def parse_enable_disable("disable_initiation"), do: {:ok, :disable_initiation}
  def parse_enable_disable(_parse_enable_disable), do: {:error, :invalid_state}

  @spec parse_reinitialized_state(String.t()) ::
          {:ok, Constants.reinitialized_state()} | {:error, term()}
  def parse_reinitialized_state("coldstart"), do: {:ok, :coldstart}
  def parse_reinitialized_state("warmstart"), do: {:ok, :warmstart}
  def parse_reinitialized_state("startbackup"), do: {:ok, :startbackup}
  def parse_reinitialized_state("endbackup"), do: {:ok, :endbackup}
  def parse_reinitialized_state("startrestore"), do: {:ok, :startrestore}
  def parse_reinitialized_state("endrestore"), do: {:ok, :endrestore}
  def parse_reinitialized_state("abortrestore"), do: {:ok, :abortrestore}
  def parse_reinitialized_state("activate_changes"), do: {:ok, :activate_changes}

  def parse_reinitialized_state(_parse_reinitialized_state),
    do: {:error, :invalid_reinitialized_state}

  @spec parse_time_duration(String.t()) :: {:ok, non_neg_integer() | nil} | {:error, term()}
  def parse_time_duration(""), do: {:ok, nil}
  def parse_time_duration("indefinite"), do: {:ok, nil}

  def parse_time_duration(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 0 and int <= 65_535 -> {:ok, int}
      _value -> {:error, :invalid_time_duration}
    end
  end

  def parse_time_duration(_value), do: {:error, :invalid_time_duration}

  @spec parse_password(String.t() | nil) :: String.t() | nil
  def parse_password(nil), do: nil
  def parse_password(""), do: nil

  def parse_password(password) when is_binary(password) do
    password = String.trim(password)
    if password == "", do: nil, else: password
  end

  def parse_password(_nil), do: nil

  @doc "Default form values for Device Communication Control."
  @spec default_dcc_form() :: map()
  def default_dcc_form() do
    %{
      "state" => "disable",
      "time_duration" => "",
      "password" => ""
    }
  end

  @doc "Default form values for Reinitialize Device."
  @spec default_reinitialize_form() :: map()
  def default_reinitialize_form() do
    %{
      "reinitialized_state" => "warmstart",
      "password" => ""
    }
  end

  @doc "Default form values for Time Synchronization."
  @spec default_time_sync_form() :: map()
  def default_time_sync_form() do
    %{"time_mode" => "local"}
  end
end
