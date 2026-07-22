defmodule BacView.BACnet.NetworkNumber do
  @moduledoc """
  Manages local BACnet network number and Network Layer What-Is / Network-Number-Is.

  * Configured `0`: unknown — learn from `Network-Number-Is`, and periodically
    send `What-Is-Network-Number` if none is observed.
  * Configured `1..65534`: answer `What-Is-Network-Number` with
    `Network-Number-Is` after a delay if nobody else responds.

  Network-layer messages are sent as **local** broadcasts only (not via BBMD/FD).
  """
  use GenServer

  require Logger

  alias BACnet.Protocol.NetworkLayerProtocolMessage
  alias BACnet.Protocol.NPCI
  alias BACnet.Stack.Client, as: StackClient
  alias BacView.BACnet.Client
  alias BacView.PubSub
  alias BacView.Settings

  @poll_ms 30_000
  @reply_delay_ms 5_000
  @topic "network_number:updates"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Configured network number from settings (0 = unknown)."
  @spec configured() :: non_neg_integer()
  def configured() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :configured)
    else
      Settings.network_number()
    end
  end

  @doc "Learned network number when configured is 0, else nil."
  @spec learned() :: non_neg_integer() | nil
  def learned() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :learned)
    else
      nil
    end
  end

  @doc """
  Effective local network number for addressing.

  Prefers learned value when configured is 0; otherwise the configured number.
  Falls back to 0 when still unknown.
  """
  @spec effective() :: non_neg_integer()
  def effective() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :effective)
    else
      Settings.network_number()
    end
  end

  @doc "Quality of the effective number: `:unknown` | `:learned` | `:configured`."
  @spec quality() :: :unknown | :learned | :configured
  def quality() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :quality)
    else
      case Settings.network_number() do
        0 -> :unknown
        _n -> :configured
      end
    end
  end

  @doc "Reload configured number from settings (clears learned when reconfigured)."
  @spec reload_from_settings() :: :ok
  def reload_from_settings() do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :reload_from_settings)
    end

    :ok
  end

  @doc """
  Forget any learned network number.

  Call after a stack restart (e.g. interface change). The GenServer itself is
  not restarted with the stack; learned state would otherwise survive on the
  wrong network.
  """
  @spec clear_learned() :: :ok
  def clear_learned() do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :clear_learned)
    end

    :ok
  end

  @doc "PubSub topic for learned/effective network number changes."
  @spec topic() :: String.t()
  def topic(), do: @topic

  @doc false
  @spec resubscribe_client() :: :ok
  def resubscribe_client() do
    if Process.whereis(__MODULE__) do
      send(__MODULE__, :resubscribe_client)
    end

    :ok
  end

  @impl true
  def init(_opts) do
    state = %{
      configured: Settings.network_number(),
      learned: nil,
      pending_reply_ref: nil,
      poll_ref: nil
    }

    maybe_subscribe_client()
    state = schedule_poll(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:configured, _from, state), do: {:reply, state.configured, state}
  def handle_call(:learned, _from, state), do: {:reply, state.learned, state}

  def handle_call(:effective, _from, state) do
    {:reply, effective_number(state), state}
  end

  def handle_call(:quality, _from, state) do
    {:reply, quality_of(state), state}
  end

  @impl true
  def handle_cast(:reload_from_settings, state) do
    configured = Settings.network_number()
    previous_learned = state.learned

    state =
      state
      |> cancel_pending_reply()
      |> Map.put(:configured, configured)
      |> Map.put(:learned, if(configured == 0, do: state.learned, else: nil))
      |> schedule_poll()

    broadcast_if_learned_changed(previous_learned, state)
    {:noreply, state}
  end

  def handle_cast(:clear_learned, state) do
    previous_learned = state.learned

    state =
      if is_nil(previous_learned) do
        state
      else
        Logger.info("Forgetting learned BACnet network number #{previous_learned}")

        state
        |> cancel_pending_reply()
        |> Map.put(:learned, nil)
        |> schedule_poll()
      end

    broadcast_if_learned_changed(previous_learned, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:resubscribe_client, state) do
    maybe_subscribe_client()
    {:noreply, state}
  end

  def handle_info(
        {:bacnet_transport, _proto, _source, {:network, _bvlc, _npci, nsdu}, _portal},
        state
      ) do
    {:noreply, handle_nsdu(state, nsdu)}
  end

  def handle_info(:poll_what_is, state) do
    state = %{state | poll_ref: nil}

    state =
      if state.configured == 0 and is_nil(state.learned) do
        _send_result = send_what_is_network_number()
        schedule_poll(state)
      else
        schedule_poll(state)
      end

    {:noreply, state}
  end

  def handle_info(:send_network_number_is, state) do
    state = %{state | pending_reply_ref: nil}

    if state.configured in 1..65_534 do
      _send_result = send_network_number_is(state.configured, :configured)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_nsdu(state, %NetworkLayerProtocolMessage{
         network_message_type: :what_is_network_number
       }) do
    state = schedule_poll(state)

    if state.configured in 1..65_534 do
      schedule_reply(state)
    else
      state
    end
  end

  defp handle_nsdu(state, %NetworkLayerProtocolMessage{
         network_message_type: :network_number_is,
         data: {dnet, _quality}
       })
       when is_integer(dnet) and dnet in 0..65_535 do
    previous_learned = state.learned

    state =
      state
      |> cancel_pending_reply()
      |> schedule_poll()

    state =
      if state.configured == 0 and dnet in 1..65_534 do
        if previous_learned != dnet do
          Logger.info("Learned BACnet network number #{dnet}")
        end

        %{state | learned: dnet}
      else
        state
      end

    broadcast_if_learned_changed(previous_learned, state)
    state
  end

  defp handle_nsdu(state, _nsdu), do: state

  defp broadcast_if_learned_changed(previous_learned, state) do
    if previous_learned != state.learned do
      Phoenix.PubSub.broadcast(
        PubSub,
        @topic,
        {:network_number_updated, %{learned: state.learned, quality: quality_of(state)}}
      )
    end

    :ok
  end

  defp schedule_reply(%{pending_reply_ref: ref} = state) when is_reference(ref), do: state

  defp schedule_reply(state) do
    ref = Process.send_after(self(), :send_network_number_is, @reply_delay_ms)
    %{state | pending_reply_ref: ref}
  end

  defp cancel_pending_reply(%{pending_reply_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | pending_reply_ref: nil}
  end

  defp cancel_pending_reply(state), do: state

  defp schedule_poll(%{configured: 0, learned: nil} = state) do
    state = cancel_poll(state)
    ref = Process.send_after(self(), :poll_what_is, @poll_ms)
    %{state | poll_ref: ref}
  end

  defp schedule_poll(state), do: cancel_poll(state)

  defp cancel_poll(%{poll_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | poll_ref: nil}
  end

  defp cancel_poll(state), do: %{state | poll_ref: nil}

  defp effective_number(%{configured: 0, learned: learned}) when is_integer(learned), do: learned
  defp effective_number(%{configured: configured}), do: configured

  defp quality_of(%{configured: configured}) when configured in 1..65_534, do: :configured
  defp quality_of(%{configured: 0, learned: learned}) when is_integer(learned), do: :learned
  defp quality_of(_state), do: :unknown

  defp maybe_subscribe_client() do
    if BacView.BACnet.Stack.running?() do
      StackClient.subscribe(Client.stack_client(), self())
    end
  rescue
    _error -> :ok
  end

  defp send_what_is_network_number() do
    msg = %NetworkLayerProtocolMessage{
      network_message_type: :what_is_network_number,
      msg_type: nil,
      data: nil
    }

    send_network_message(msg)
  end

  defp send_network_number_is(dnet, quality) when quality in [:configured, :learned] do
    msg = %NetworkLayerProtocolMessage{
      network_message_type: :network_number_is,
      msg_type: nil,
      data: {dnet, quality}
    }

    send_network_message(msg)
  end

  defp send_network_message(%NetworkLayerProtocolMessage{} = msg) do
    with true <- BacView.BACnet.Stack.running?(),
         client <- Client.stack_client(),
         {:ok, nsdu_bin} <- NetworkLayerProtocolMessage.encode(msg),
         {trans_mod, _transport, portal} <- StackClient.get_transport(client),
         {:ok, broadcast} <- GenServer.call(client, :get_broadcast_address) do
      npci =
        NPCI.new(
          is_network_message: true,
          expects_reply: false
        )

      case trans_mod.send(portal, broadcast, nsdu_bin, npci: npci, expects_reply: false) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.debug("NetworkNumber send failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      reason ->
        Logger.debug("NetworkNumber send skipped: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.debug("NetworkNumber send error: #{inspect(error)}")
      {:error, error}
  end
end
