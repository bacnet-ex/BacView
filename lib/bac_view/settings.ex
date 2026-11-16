defmodule BacView.Settings do
  @moduledoc """
  Runtime BACnet stack and COV settings, persisted to disk.
  """
  use GenServer

  alias BACnet.Protocol.SecureConnect.BVLC
  alias BACnet.Stack.Transport.ScTransport.Config, as: SCConfig
  alias BacView.BACnet.Address
  alias BacView.BACnet.InterfaceSelection

  @settings_file "runtime_settings.json"

  @stack_keys ~w(transport interface ipv4_port mstp_local_address mstp_baud_rate
                 sc_primary_hub_uri sc_failover_hub_uri sc_verify_hostname sc_ip_family)a
  @mstp_enabled Application.compile_env!(:bacview, :mstp_enabled)
  @supported_transports if @mstp_enabled, do: ~w(ipv4 mstp bacnet_sc), else: ~w(ipv4 bacnet_sc)

  @apdu_timeout_min 100
  @apdu_timeout_max 60_000
  @apdu_retries_min 0
  @apdu_retries_max 16
  @max_segments_values [2, 4, 8, 16, 32, 64]

  @type max_segments :: 2 | 4 | 8 | 16 | 32 | 64 | :more_than_64

  @type t :: %{
          transport: String.t(),
          interface: String.t() | nil,
          ipv4_port: pos_integer(),
          device_id: pos_integer(),
          network_number: non_neg_integer(),
          max_apdu_length: 50..1476,
          apdu_timeout: pos_integer(),
          apdu_retries: non_neg_integer(),
          apdu_segments_timeout: pos_integer(),
          max_segments: max_segments(),
          cov_lifetime_seconds: non_neg_integer(),
          cov_confirmed: boolean(),
          scan_on_online: boolean(),
          cov_increment: float() | nil,
          mstp_local_address: 0..127,
          mstp_baud_rate: :auto | pos_integer(),
          sc_primary_hub_uri: String.t() | nil,
          sc_failover_hub_uri: String.t() | nil,
          sc_verify_hostname: boolean(),
          sc_ip_family: String.t(),
          sc_device_uuid: String.t() | nil,
          sc_vmac: String.t() | nil,
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

  @spec scan_on_online?() :: boolean()
  def scan_on_online?(), do: get().scan_on_online

  @spec cov_increment() :: float() | nil
  def cov_increment(), do: get().cov_increment

  @spec device_id() :: pos_integer()
  def device_id(), do: get().device_id

  @spec network_number() :: non_neg_integer()
  def network_number(), do: get().network_number

  @spec max_apdu_length() :: 50..1476
  def max_apdu_length(), do: get().max_apdu_length

  @spec apdu_timeout() :: pos_integer()
  def apdu_timeout(), do: get().apdu_timeout

  @spec apdu_retries() :: non_neg_integer()
  def apdu_retries(), do: get().apdu_retries

  @spec apdu_segments_timeout() :: pos_integer()
  def apdu_segments_timeout(), do: get().apdu_segments_timeout

  @spec max_segments() :: max_segments()
  def max_segments(), do: get().max_segments

  @spec apdu_timeout_min() :: pos_integer()
  def apdu_timeout_min(), do: @apdu_timeout_min

  @spec apdu_timeout_max() :: pos_integer()
  def apdu_timeout_max(), do: @apdu_timeout_max

  @spec apdu_retries_min() :: non_neg_integer()
  def apdu_retries_min(), do: @apdu_retries_min

  @spec apdu_retries_max() :: non_neg_integer()
  def apdu_retries_max(), do: @apdu_retries_max

  @spec max_segments_values() :: [2 | 4 | 8 | 16 | 32 | 64]
  def max_segments_values(), do: @max_segments_values

  @spec transport() :: String.t()
  def transport(), do: get().transport

  @spec interface() :: String.t() | nil
  def interface(), do: get().interface

  @spec defaults() :: t()
  def defaults() do
    %{
      transport: "ipv4",
      interface: nil,
      ipv4_port: Address.default_ipv4_port(),
      device_id: 4_194_302,
      network_number: 0,
      max_apdu_length: 1476,
      apdu_timeout: 3_000,
      apdu_retries: 3,
      apdu_segments_timeout: 3_000,
      max_segments: 64,
      cov_lifetime_seconds: 3600,
      cov_confirmed: false,
      scan_on_online: false,
      cov_increment: nil,
      mstp_local_address: 127,
      mstp_baud_rate: :auto,
      sc_primary_hub_uri: nil,
      sc_failover_hub_uri: nil,
      sc_verify_hostname: false,
      sc_ip_family: "inet",
      sc_device_uuid: nil,
      sc_vmac: nil,
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

  @spec ensure_sc_identity() :: {:ok, %{uuid: binary(), vmac: binary()}} | {:error, term()}
  def ensure_sc_identity(), do: GenServer.call(__MODULE__, :ensure_sc_identity)

  @spec persist_sc_vmac(binary()) :: :ok | {:error, term()}
  def persist_sc_vmac(vmac), do: GenServer.call(__MODULE__, {:persist_sc_vmac, vmac})

  @impl true
  def init(_opts) do
    state = reconcile_interface(load_settings())
    :ok = persist(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:update, opts}, _from, state) do
    case validate_updates(state, opts) do
      {:ok, new_state} ->
        new_state = reconcile_interface(new_state)

        case persist(new_state) do
          :ok -> {:reply, {:ok, new_state}, new_state}
          {:error, _reason} = error -> {:reply, error, state}
        end

      {:error, _get} = err ->
        {:reply, err, state}
    end
  end

  def handle_call(:ensure_sc_identity, _from, state) do
    uuid = load_sc_uuid(state.sc_device_uuid)
    vmac = load_sc_vmac(state.sc_vmac)
    updated = %{state | sc_device_uuid: Base.encode16(uuid), sc_vmac: Base.encode16(vmac)}

    if updated == state or persist(updated) == :ok do
      {:reply, {:ok, %{uuid: uuid, vmac: vmac}}, updated}
    else
      {:reply, {:error, :sc_identity_storage_failed}, state}
    end
  end

  def handle_call({:persist_sc_vmac, <<_value::48>> = vmac}, _from, state) do
    updated = %{state | sc_vmac: Base.encode16(vmac)}

    if BVLC.valid_vmac?(vmac) and persist(updated) == :ok do
      {:reply, :ok, updated}
    else
      {:reply, {:error, :sc_identity_storage_failed}, state}
    end
  end

  def handle_call({:persist_sc_vmac, _vmac}, _from, state),
    do: {:reply, {:error, :invalid_sc_vmac}, state}

  defp load_sc_uuid(value) do
    case Base.decode16(to_string(value), case: :mixed) do
      {:ok, <<uuid::128>> = binary} when uuid != 0 ->
        binary

      _invalid ->
        <<prefix::48, _version::4, middle::12, _variant::2, suffix::62>> =
          :crypto.strong_rand_bytes(16)

        <<prefix::48, 4::4, middle::12, 2::2, suffix::62>>
    end
  end

  defp load_sc_vmac(value) do
    with {:ok, vmac} <- Base.decode16(to_string(value), case: :mixed),
         true <- BVLC.valid_vmac?(vmac) do
      vmac
    else
      _invalid -> BVLC.random_vmac()
    end
  end

  @spec validate_sc_config(t()) :: :ok | {:error, :invalid_hub_uri | :missing_sc_primary_hub}
  def validate_sc_config(settings) do
    with {:ok, primary} <- SCConfig.uri(settings.sc_primary_hub_uri),
         :ok <- require_sc_primary(primary),
         {:ok, _failover} <- SCConfig.uri(settings.sc_failover_hub_uri) do
      :ok
    end
  end

  defp require_sc_primary(nil), do: {:error, :missing_sc_primary_hub}
  defp require_sc_primary(%URI{}), do: :ok

  defp validate_updates(state, opts) do
    with {:ok, updated} <- apply_updates(state, opts),
         :ok <- validate_selected_transport(updated) do
      {:ok, updated}
    end
  end

  defp validate_selected_transport(%{transport: "bacnet_sc"} = settings),
    do: validate_sc_config(settings)

  defp validate_selected_transport(_settings), do: :ok

  defp apply_updates(state, opts) do
    Enum.reduce_while(opts, {:ok, state}, fn
      {:transport, value}, {:ok, acc} ->
        if value in supported_transports() do
          {:cont, {:ok, %{acc | transport: value}}}
        else
          {:halt, {:error, :invalid_transport}}
        end

      {:interface, nil}, {:ok, %{transport: "bacnet_sc"} = acc} ->
        {:cont, {:ok, acc}}

      {:interface, value}, {:ok, acc} when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:halt, {:error, :invalid_interface}}
        else
          {:cont, {:ok, %{acc | interface: trimmed}}}
        end

      {:ipv4_port, value}, {:ok, acc} when is_integer(value) and value in 47_808..65_535 ->
        {:cont, {:ok, %{acc | ipv4_port: value}}}

      {:device_id, value}, {:ok, acc} when is_integer(value) and value in 0..4_194_303 ->
        {:cont, {:ok, %{acc | device_id: value}}}

      {:network_number, value}, {:ok, acc} when is_integer(value) and value in 0..65_534 ->
        {:cont, {:ok, %{acc | network_number: value}}}

      {:max_apdu_length, value}, {:ok, acc} when is_integer(value) and value in 50..1476 ->
        {:cont, {:ok, %{acc | max_apdu_length: value}}}

      {:apdu_timeout, value}, {:ok, acc}
      when is_integer(value) and value in @apdu_timeout_min..@apdu_timeout_max ->
        {:cont, {:ok, %{acc | apdu_timeout: value}}}

      {:apdu_retries, value}, {:ok, acc}
      when is_integer(value) and value in @apdu_retries_min..@apdu_retries_max ->
        {:cont, {:ok, %{acc | apdu_retries: value}}}

      {:apdu_segments_timeout, value}, {:ok, acc}
      when is_integer(value) and value in @apdu_timeout_min..@apdu_timeout_max ->
        {:cont, {:ok, %{acc | apdu_segments_timeout: value}}}

      {:max_segments, :more_than_64}, {:ok, acc} ->
        {:cont, {:ok, %{acc | max_segments: :more_than_64}}}

      {:max_segments, value}, {:ok, acc} when value in @max_segments_values ->
        {:cont, {:ok, %{acc | max_segments: value}}}

      {:cov_lifetime_seconds, value}, {:ok, acc} when is_integer(value) and value >= 0 ->
        {:cont, {:ok, %{acc | cov_lifetime_seconds: value}}}

      {:cov_confirmed, value}, {:ok, acc} when is_boolean(value) ->
        {:cont, {:ok, %{acc | cov_confirmed: value}}}

      {:scan_on_online, value}, {:ok, acc} when is_boolean(value) ->
        {:cont, {:ok, %{acc | scan_on_online: value}}}

      {:cov_increment, nil}, {:ok, acc} ->
        {:cont, {:ok, %{acc | cov_increment: nil}}}

      {:cov_increment, value}, {:ok, acc} when is_number(value) and value >= 0 ->
        {:cont, {:ok, %{acc | cov_increment: value * 1.0}}}

      {:mstp_local_address, value}, {:ok, acc} when is_integer(value) and value in 0..127 ->
        {:cont, {:ok, %{acc | mstp_local_address: value}}}

      {:mstp_baud_rate, :auto}, {:ok, acc} ->
        {:cont, {:ok, %{acc | mstp_baud_rate: :auto}}}

      {:mstp_baud_rate, value}, {:ok, acc}
      when is_integer(value) and value in [9600, 19_200, 38_400, 57_600, 76_800, 115_200] ->
        {:cont, {:ok, %{acc | mstp_baud_rate: value}}}

      {key, value}, {:ok, acc}
      when key in [:sc_primary_hub_uri, :sc_failover_hub_uri] and is_binary(value) ->
        trimmed = empty_to_nil(String.trim(value))

        case SCConfig.uri(trimmed) do
          {:ok, _uri} -> {:cont, {:ok, Map.put(acc, key, trimmed)}}
          {:error, _reason} = error -> {:halt, error}
        end

      {key, nil}, {:ok, acc} when key in [:sc_primary_hub_uri, :sc_failover_hub_uri] ->
        {:cont, {:ok, Map.put(acc, key, nil)}}

      {:sc_verify_hostname, value}, {:ok, acc} when is_boolean(value) ->
        {:cont, {:ok, %{acc | sc_verify_hostname: value}}}

      {:sc_ip_family, value}, {:ok, acc} when value in ["inet", "inet6"] ->
        {:cont, {:ok, %{acc | sc_ip_family: value}}}

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

  @doc false
  @spec supported_transports() :: [String.t()]
  def supported_transports(), do: @supported_transports

  defp load_settings() do
    path = settings_path()

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, map} when is_map(map) ->
            map
            |> migrate_legacy_keys()
            |> merge_defaults()

          _load_settings ->
            defaults()
        end

      {:error, :enoent} ->
        defaults()

      {:error, _load_settings} ->
        defaults()
    end
  end

  # Persist key was renamed; keep existing user preference.
  defp migrate_legacy_keys(map) do
    case Map.pop(map, "auto_scan_on_iam") do
      {nil, rest} -> rest
      {value, rest} -> Map.put_new(rest, "scan_on_online", value)
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
    |> update_in([:scan_on_online], &to_bool/1)
    |> update_in([:cov_increment], &parse_cov_increment/1)
    |> update_in([:mstp_baud_rate], &normalize_mstp_baud_rate/1)
    |> update_in([:sc_verify_hostname], &to_bool/1)
    |> update_in([:sc_ip_family], &normalize_sc_ip_family/1)
    |> update_in([:sc_device_uuid], &optional_binary/1)
    |> update_in([:sc_vmac], &optional_binary/1)
    |> update_in([:bbmd_host], &empty_to_nil/1)
    |> update_in([:network_number], &normalize_network_number/1)
    |> update_in([:max_apdu_length], &normalize_max_apdu_length/1)
    |> update_in([:apdu_timeout], &normalize_apdu_timeout/1)
    |> update_in([:apdu_retries], &normalize_apdu_retries/1)
    |> update_in([:apdu_segments_timeout], &normalize_apdu_timeout/1)
    |> update_in([:max_segments], &normalize_max_segments/1)
    |> maybe_coerce_mstp_transport()
  end

  defp normalize_sc_ip_family("inet6"), do: "inet6"
  defp normalize_sc_ip_family(_family), do: "inet"

  defp optional_binary(value) when is_binary(value), do: value
  defp optional_binary(_value), do: nil

  defp normalize_network_number(value) when is_integer(value) and value in 0..65_534, do: value

  defp normalize_network_number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_network_number(int)
      _other -> 0
    end
  end

  defp normalize_network_number(_value), do: 0

  defp normalize_max_apdu_length(value) when is_integer(value) and value in 50..1476, do: value

  defp normalize_max_apdu_length(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_max_apdu_length(int)
      _other -> 1476
    end
  end

  defp normalize_max_apdu_length(_value), do: 1476

  defp normalize_apdu_timeout(value)
       when is_integer(value) and value in @apdu_timeout_min..@apdu_timeout_max,
       do: value

  defp normalize_apdu_timeout(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_apdu_timeout(int)
      _other -> 3_000
    end
  end

  defp normalize_apdu_timeout(_value), do: 3_000

  defp normalize_apdu_retries(value)
       when is_integer(value) and value in @apdu_retries_min..@apdu_retries_max,
       do: value

  defp normalize_apdu_retries(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_apdu_retries(int)
      _other -> 3
    end
  end

  defp normalize_apdu_retries(_value), do: 3

  defp normalize_max_segments(:more_than_64), do: :more_than_64
  defp normalize_max_segments("more_than_64"), do: :more_than_64
  defp normalize_max_segments(value) when value in @max_segments_values, do: value

  defp normalize_max_segments(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> normalize_max_segments(int)
      _other -> :more_than_64
    end
  end

  defp normalize_max_segments(_value), do: :more_than_64

  if not @mstp_enabled do
    defp maybe_coerce_mstp_transport(%{transport: "mstp"} = settings) do
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
    temporary = path <> "." <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    data = Jason.encode!(Map.drop(state, [:interface_error]), pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary, data, [:exclusive, :sync]),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp settings_path() do
    Application.get_env(:bacview, :runtime_settings_path) ||
      System.get_env("BACVIEW_SETTINGS_PATH") ||
      Path.join(:code.priv_dir(:bacview), @settings_file)
  end
end
