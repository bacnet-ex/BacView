defmodule BacView.LogStore do
  @moduledoc """
  In-memory ring buffer of Logger events for the in-app log viewer.

  Optionally appends to a log file (desktop / configured path). A `:logger`
  handler forwards events here without calling Logger again (re-entrancy safe).
  """
  use GenServer

  @default_max_lines 2_000
  @topic "logs:app"
  @handler_id :bacview_log_store
  @max_message_bytes 4_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Attach the logger handler (idempotent)."
  @spec attach() :: :ok | {:error, term()}
  def attach() do
    case :logger.add_handler(@handler_id, BacView.LogStore.Handler, %{
           level: :debug,
           filter_default: :log,
           filters: []
         }) do
      :ok -> :ok
      {:error, {:already_exist, _id}} -> :ok
      other -> other
    end
  end

  @doc "Detach the logger handler."
  @spec detach() :: :ok | {:error, term()}
  def detach() do
    :logger.remove_handler(@handler_id)
  end

  @doc "Recent log entries, newest last."
  @spec list(keyword()) :: [map()]
  def list(opts \\ []) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:list, opts})
    else
      []
    end
  end

  @doc "Clear the in-memory buffer (file is left intact)."
  @spec clear() :: :ok
  def clear() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  @doc "Configured log file path (may be nil if file logging disabled)."
  @spec path() :: String.t() | nil
  def path() do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :path)
    else
      nil
    end
  end

  @doc "Subscribe the calling process to live log PubSub events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe() do
    Phoenix.PubSub.subscribe(BacView.PubSub, @topic)
  end

  @doc false
  @spec ingest(map()) :: :ok
  def ingest(event) when is_map(event) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:ingest, event})
    end

    :ok
  end

  @impl true
  def init(_opts) do
    max_lines = Application.get_env(:bacview, :log_store_max_lines, @default_max_lines)
    path = resolve_log_path()

    if path do
      File.mkdir_p!(Path.dirname(path))
    end

    state = %{
      entries: :queue.new(),
      size: 0,
      max_lines: max_lines,
      path: path,
      next_id: 1
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:list, opts}, _from, state) do
    level = Keyword.get(opts, :level)
    limit = Keyword.get(opts, :limit, state.max_lines)

    entries =
      state.entries
      |> :queue.to_list()
      |> maybe_filter_level(level)
      |> Enum.take(-limit)

    {:reply, entries, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | entries: :queue.new(), size: 0}}
  end

  def handle_call(:path, _from, state), do: {:reply, state.path, state}

  @impl true
  def handle_cast({:ingest, event}, state) do
    entry = normalize_event(event, state.next_id)
    state = push_entry(state, entry)
    maybe_write_file(state.path, entry)
    _broadcast = Phoenix.PubSub.broadcast(BacView.PubSub, @topic, {:log_entry, entry})
    {:noreply, %{state | next_id: state.next_id + 1}}
  end

  defp push_entry(%{size: size, max_lines: max} = state, entry) when size >= max do
    {_dropped, queue} = :queue.out(state.entries)
    %{state | entries: :queue.in(entry, queue), size: size}
  end

  defp push_entry(%{size: size} = state, entry) do
    %{state | entries: :queue.in(entry, state.entries), size: size + 1}
  end

  defp normalize_event(event, id) do
    level = Map.get(event, :level, :info)
    message = truncate_message(Map.get(event, :message, ""))
    time = Map.get(event, :time) || DateTime.utc_now()
    metadata = Map.get(event, :metadata, %{})

    %{
      id: id,
      level: level,
      message: message,
      time: time,
      metadata: metadata
    }
  end

  defp truncate_message(message) when is_binary(message) do
    if byte_size(message) > @max_message_bytes do
      binary_part(message, 0, @max_message_bytes) <> "…"
    else
      message
    end
  end

  defp truncate_message(message), do: truncate_message(to_string(message))

  defp maybe_filter_level(entries, nil), do: entries

  defp maybe_filter_level(entries, level) when is_atom(level) do
    Enum.filter(entries, fn entry ->
      Logger.compare_levels(entry.level, level) != :lt
    end)
  end

  defp maybe_write_file(nil, _entry), do: :ok

  defp maybe_write_file(path, entry) do
    line =
      [
        DateTime.to_iso8601(entry.time),
        " [",
        Atom.to_string(entry.level),
        "] ",
        entry.message,
        "\n"
      ]

    _write_result = File.write(path, line, [:append])
    :ok
  rescue
    _error -> :ok
  end

  defp resolve_log_path() do
    cond do
      path = Application.get_env(:bacview, :log_store_path) ->
        path

      path = System.get_env("BACVIEW_LOG_PATH") ->
        path

      Application.get_env(:bacview, :log_store_enabled) == false ->
        nil

      Application.get_env(:bacview, :desktop_mode, false) ->
        Path.join([System.user_home!(), ".config", "bacview", "bacview.log"])

      true ->
        Path.expand("tmp/bacview.log")
    end
  rescue
    _error -> nil
  end
end
