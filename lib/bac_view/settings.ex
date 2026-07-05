defmodule BacView.Settings do
  @moduledoc """
  Runtime BACnet stack and COV settings, persisted to disk.
  """
  use GenServer

  alias BacView.BACnet.InterfaceSelection

  @settings_file "runtime_settings.json"

  @stack_keys ~w(transport interface mstp_local_address mstp_baud_rate)a
  @mstp_enabled Application.compile_env!(:bacview, :mstp_enabled)
  @supported_transports if @mstp_enabled, do: ~w(ipv4 mstp), else: ~w(ipv4)

  @type t :: %{
          transport: String.t(),
          interface: String.t() | nil,
          device_id: pos_integer(),
          network_number: pos_integer(),
          cov_lifetime_seconds: non_neg_integer(),
          cov_confirmed: boolean(),
          cov_increment: float() | nil,
          mstp_local_address: 0..127,
          mstp_baud_rate: :auto | pos_integer(),
          bbmd_host: String.t() | nil,
          bbmd_port: pos_integer(),
          bbmd_ttl: pos_integer(),
          interface_error: atom() | nil
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get() :: t()
  def get() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :get)
    else
      defaults()
    end
  end

  @spec update(keyword()) :: {:ok, t()} | {:error, term()}
  def update(opts) when is_list(opts), do: GenServer.call(__MODULE__, {:update, opts})

  @spec cov_lifetime() :: non_neg_integer()
  def cov_lifetime(), do: get().cov_lifetime_seconds

  @spec cov_confirmed?() :: boolean()
  def cov_confirmed?(), do: get().cov_confirmed

  @spec cov_increment() :: float() | nil
  def cov_increment(), do: get().cov_increment

  @spec device_id() :: pos_integer()
  def device_id(), do: get().device_id

  @spec network_number() :: pos_integer()
  def network_number(), do: get().network_number

  @spec transport() :: String.t()
  def transport(), do: get().transport

  @spec interface() :: String.t() | nil
  def interface(), do: get().interface

  @spec defaults() :: t()
  def defaults() do
    %{
      transport: "ipv4",
      interface: nil,
      device_id: 4_194_302,
      network_number: 1,
      cov_lifetime_seconds: 3600,
      cov_confirmed: false,
      cov_increment: nil,
      mstp_local_address: 127,
      mstp_baud_rate: :auto,
      bbmd_host: nil,
      bbmd_port: 47_808,
      bbmd_ttl: 600,
      interface_error: nil
    }
  end

  @spec stack_restart_required?(t(), t()) :: boolean()
  def stack_restart_required?(before, after_map) do
    Enum.any?(@stack_keys, fn key ->
      Map.get(before, key) != Map.get(after_map, key)
    end)
  end

  @spec interface_options(String.t()) :: [map()]
  def interface_options(transport), do: InterfaceSelection.options_for(transport)

  @spec reconcile_interface(t()) :: t()
  def reconcile_interface(settings) do
    case InterfaceSelection.resolve(settings.transport, settings.interface) do
      {:ok, %{interface: interface}} ->
        %{settings | interface: interface, interface_error: nil}

      {:error, error, %{interface: interface}} ->
        %{settings | interface: interface, interface_error: error}
    end
  end

  @impl true
  def init(_opts) do
    reconcile_interface(state = load_settings())
    persist(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:update, opts}, _from, state) do
    case apply_updates(state, opts) do
      {:ok, new_state} ->
        new_state = reconcile_interface(new_state)
        persist(new_state)
        {:reply, {:ok, new_state}, new_state}

      {:error, _get} = err ->
        {:reply, err, state}
    end
  end

  defp apply_updates(state, opts) do
    Enum.reduce_while(opts, {:ok, state}, fn
      {:transport, value}, {:ok, acc} ->
        if value in supported_transports() do
          {:cont, {:ok, %{acc | transport: value}}}
        else
          {:halt, {:error, :invalid_transport}}
        end

      {:interface, value}, {:ok, acc} when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:halt, {:error, :invalid_interface}}
        else
          {:cont, {:ok, %{acc | interface: trimmed}}}
        end

      {:device_id, value}, {:ok, acc} when is_integer(value) and value in 0..4_194_303 ->
        {:cont, {:ok, %{acc | device_id: value}}}

      {:network_number, value}, {:ok, acc} when is_integer(value) and value in 1..65_535 ->
        {:cont, {:ok, %{acc | network_number: value}}}

      {:cov_lifetime_seconds, value}, {:ok, acc} when is_integer(value) and value >= 0 ->
        {:cont, {:ok, %{acc | cov_lifetime_seconds: value}}}

      {:cov_confirmed, value}, {:ok, acc} when is_boolean(value) ->
        {:cont, {:ok, %{acc | cov_confirmed: value}}}

      {:cov_increment, nil}, {:ok, acc} ->
        {:cont, {:ok, %{acc | cov_increment: nil}}}

      {:cov_increment, value}, {:ok, acc} when is_float(value) and value >= 0 ->
        {:cont, {:ok, %{acc | cov_increment: value}}}

      {:mstp_local_address, value}, {:ok, acc} when is_integer(value) and value in 0..127 ->
        {:cont, {:ok, %{acc | mstp_local_address: value}}}

      {:mstp_baud_rate, :auto}, {:ok, acc} ->
        {:cont, {:ok, %{acc | mstp_baud_rate: :auto}}}

      {:mstp_baud_rate, value}, {:ok, acc}
      when is_integer(value) and value in [9600, 19_200, 38_400, 57_600, 76_800, 115_200] ->
        {:cont, {:ok, %{acc | mstp_baud_rate: value}}}

      {:bbmd_host, value}, {:ok, acc} when is_binary(value) ->
        {:cont, {:ok, %{acc | bbmd_host: String.trim(value)}}}

      {:bbmd_host, nil}, {:ok, acc} ->
        {:cont, {:ok, %{acc | bbmd_host: nil}}}

      {:bbmd_port, value}, {:ok, acc} when is_integer(value) and value in 1..65_535 ->
        {:cont, {:ok, %{acc | bbmd_port: value}}}

      {:bbmd_ttl, value}, {:ok, acc} when is_integer(value) and value > 0 ->
        {:cont, {:ok, %{acc | bbmd_ttl: value}}}

      _state, {:ok, _acc} ->
        {:halt, {:error, :invalid_settings}}

      _state, err ->
        {:halt, err}
    end)
  end

  defp supported_transports(), do: @supported_transports

  defp load_settings() do
    path = settings_path()

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, map} when is_map(map) -> merge_defaults(map)
          _load_settings -> defaults()
        end

      {:error, :enoent} ->
        defaults()

      {:error, _load_settings} ->
        defaults()
    end
  end

  defp merge_defaults(map) do
    defaults()
    |> Map.merge(atomize_map(map), fn _key, default, loaded ->
      if is_nil(loaded), do: default, else: loaded
    end)
    |> normalize_loaded()
  end

  defp atomize_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_binary(key) ->
        case safe_atom(key) do
          {:ok, atom} -> Map.put(acc, atom, value)
          :error -> acc
        end

      _map, acc ->
        acc
    end)
  end

  defp safe_atom(key) do
    if Map.has_key?(defaults(), String.to_existing_atom(key)) do
      {:ok, String.to_existing_atom(key)}
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  defp normalize_loaded(settings) do
    settings
    |> update_in([:cov_confirmed], &to_bool/1)
    |> update_in([:cov_increment], &parse_cov_increment/1)
    |> update_in([:mstp_baud_rate], &normalize_mstp_baud_rate/1)
    |> update_in([:bbmd_host], &empty_to_nil/1)
    |> maybe_coerce_mstp_transport()
  end

  defp maybe_coerce_mstp_transport(%{transport: "mstp"} = settings) do
    if @mstp_enabled do
      settings
    else
      %{settings | transport: "ipv4", interface: nil}
    end
  end

  defp maybe_coerce_mstp_transport(settings), do: settings

  defp normalize_mstp_baud_rate(:auto), do: :auto
  defp normalize_mstp_baud_rate("auto"), do: :auto

  defp normalize_mstp_baud_rate(value)
       when is_integer(value) and
              value in [9600, 19_200, 38_400, 57_600, 76_800, 115_200],
       do: value

  defp normalize_mstp_baud_rate(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_mstp_baud_rate(int)
      _auto -> :auto
    end
  end

  defp normalize_mstp_baud_rate(_auto), do: :auto

  defp to_bool(true), do: true
  defp to_bool(false), do: false
  defp to_bool("true"), do: true
  defp to_bool("false"), do: false
  defp to_bool(_true), do: false

  defp parse_cov_increment(nil), do: nil
  defp parse_cov_increment(""), do: nil

  defp parse_cov_increment(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _nil -> nil
    end
  end

  defp parse_cov_increment(value) when is_number(value), do: value * 1.0
  defp parse_cov_increment(_nil), do: nil

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp persist(state) do
    path = settings_path()
    File.mkdir_p!(Path.dirname(path))

    state
    |> Map.drop([:interface_error])
    |> Jason.encode!(pretty: true)
    |> then(&File.write!(path, &1))
  end

  defp settings_path() do
    Application.get_env(:bacview, :runtime_settings_path) ||
      System.get_env("BACVIEW_SETTINGS_PATH") ||
      Path.join(:code.priv_dir(:bacview), @settings_file)
  end
end
