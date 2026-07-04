defmodule BacView.BACnet.Client do
  @moduledoc """
  High-level BACnet client facade over bacstack `ClientHelper`.
  """

  alias BACnet.Protocol.APDU
  alias BACnet.Protocol.ApplicationTags
  alias BACnet.Protocol.ApplicationTags.Encoding
  alias BACnet.Protocol.Destination
  alias BACnet.Protocol.ObjectIdentifier
  alias BACnet.Protocol.Services
  alias BACnet.Protocol.Services.Ack.ReadRangeAck
  alias BACnet.Stack.Client
  alias BACnet.Stack.ClientHelper

  @type destination :: term()
  @type read_result :: {:ok, term()} | {:error, term()}
  @type write_result :: :ok | {:error, term()}

  @doc "Returns the underlying bacstack client process."
  @spec stack_client() :: GenServer.server()
  def stack_client(), do: BacView.BACnet.Stack.client()

  @spec who_is(timeout :: non_neg_integer(), keyword()) :: read_result
  def who_is(timeout \\ 5_000, opts \\ []) do
    case BacView.BACnet.ForeignRegistration.who_is(timeout, opts) do
      :use_local ->
        case ClientHelper.who_is(stack_client(), timeout, opts) do
          {:ok, responses} -> {:ok, responses}
          other -> normalize_error(other)
        end

      {:ok, responses} ->
        {:ok, responses}

      {:error, _5_000} = err ->
        err
    end
  end

  @spec read_property(destination(), ObjectIdentifier.t(), atom() | integer(), keyword()) ::
          read_result
  def read_property(destination, object, property, opts \\ []) do
    array_index = Keyword.get(opts, :array_index)
    read_opts = Keyword.delete(opts, :array_index)

    case ClientHelper.read_property(
           stack_client(),
           destination,
           object,
           property,
           array_index,
           read_opts
         ) do
      {:ok, value} -> {:ok, value}
      other -> normalize_error(other)
    end
  end

  @spec read_property_multiple(
          destination(),
          ObjectIdentifier.t(),
          [atom() | integer()],
          keyword()
        ) :: read_result
  def read_property_multiple(destination, object, properties, opts \\ []) do
    case ClientHelper.read_property_multiple(
           stack_client(),
           destination,
           object,
           properties,
           opts
         ) do
      {:ok, results} -> {:ok, results}
      other -> normalize_error(other)
    end
  end

  @spec read_object(destination(), ObjectIdentifier.t(), keyword()) :: read_result
  def read_object(destination, object, opts \\ []) do
    case ClientHelper.read_object(stack_client(), destination, object, opts) do
      {:ok, obj} -> {:ok, obj}
      other -> normalize_error(other)
    end
  end

  @spec scan_device(destination(), ObjectIdentifier.t(), keyword()) :: read_result
  def scan_device(destination, device, opts \\ []) do
    case ClientHelper.scan_device(stack_client(), destination, device, opts) do
      {:ok, objects} -> {:ok, objects}
      other -> normalize_error(other)
    end
  end

  @spec write_property(
          destination(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term(),
          keyword()
        ) :: write_result
  def write_property(destination, object, property, value, opts \\ []) do
    case ClientHelper.write_property(
           stack_client(),
           destination,
           object,
           property,
           value,
           opts
         ) do
      :ok -> :ok
      other -> normalize_error(other)
    end
  end

  @spec subscribe_cov_property(
          destination(),
          ObjectIdentifier.t(),
          atom() | integer(),
          keyword()
        ) :: :ok | {:error, term()}
  def subscribe_cov_property(destination, object, property, opts \\ []) do
    case ClientHelper.subscribe_cov_property(
           stack_client(),
           destination,
           object,
           property,
           opts
         ) do
      :ok -> :ok
      other -> normalize_error(other)
    end
  end

  @doc """
  Subscribes to COV notifications for an entire object (Present_Value by default).
  """
  @spec subscribe_cov(destination(), ObjectIdentifier.t(), keyword()) :: :ok | {:error, term()}
  def subscribe_cov(destination, %ObjectIdentifier{} = object, opts \\ []) do
    lifetime = Keyword.get(opts, :lifetime, 3600)
    confirmed = if lifetime, do: Keyword.get(opts, :confirmed, false), else: nil

    pid =
      Keyword.get_lazy(opts, :pid, fn ->
        [node, pid, pid2] =
          self()
          |> :erlang.pid_to_list()
          |> :binary.list_to_bin()
          |> then(&Regex.scan(~r/<(\d+)\.(\d+)\.(\d+)>/, &1))
          |> hd()
          |> tl()
          |> Enum.map(&String.to_integer/1)

        Bitwise.bsl(Bitwise.band(node, 0x0F), 28) + Bitwise.bsl(pid, 13) + pid2
      end)

    with {:ok, req} <-
           Services.SubscribeCov.to_apdu(
             %Services.SubscribeCov{
               process_identifier: pid,
               monitored_object: object,
               issue_confirmed_notifications: confirmed,
               lifetime: lifetime
             },
             opts
           ),
         {:ok, %APDU.SimpleACK{}} <- Client.send(stack_client(), destination, req, opts) do
      :ok
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  @spec add_list_element(
          destination(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term() | [term()],
          keyword()
        ) :: :ok | {:error, term()}
  def add_list_element(destination, object, property, elements, opts \\ []) do
    send_list_element(
      destination,
      object,
      property,
      elements,
      Services.AddListElement,
      opts
    )
  end

  @spec remove_list_element(
          destination(),
          ObjectIdentifier.t(),
          atom() | integer(),
          term() | [term()],
          keyword()
        ) :: :ok | {:error, term()}
  def remove_list_element(destination, object, property, elements, opts \\ []) do
    send_list_element(
      destination,
      object,
      property,
      elements,
      Services.RemoveListElement,
      opts
    )
  end

  @doc false
  @spec encode_list_elements([term()]) :: {:ok, [Encoding.t()]} | {:error, term()}
  def encode_list_elements(elements) when is_list(elements) do
    Enum.reduce_while(elements, {:ok, []}, fn element, {:ok, acc} ->
      case encode_list_element(element) do
        {:ok, encoded} ->
          {:cont, {:ok, acc ++ List.wrap(encoded)}}

        {:error, _elements} = err ->
          {:halt, err}
      end
    end)
  end

  @spec read_range(
          destination(),
          ObjectIdentifier.t(),
          atom() | integer(),
          Services.ReadRange.range() | nil,
          keyword()
        ) :: {:ok, ReadRangeAck.t()} | {:error, term()}
  def read_range(destination, object, property, range \\ nil, opts \\ []) do
    with {:ok, req} <-
           Services.ReadRange.to_apdu(
             %Services.ReadRange{
               object_identifier: object,
               property_identifier: property,
               property_array_index: nil,
               range: range
             },
             opts
           ),
         {:ok, %APDU.ComplexACK{} = ack} <- Client.send(stack_client(), destination, req, opts),
         {:ok, response} <- ReadRangeAck.from_apdu(ack) do
      {:ok, response}
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  @doc "Sends Device Communication Control to a remote BACnet device."
  @spec device_communication_control(
          destination(),
          BACnet.Protocol.Constants.enable_disable(),
          ApplicationTags.unsigned16() | nil,
          String.t() | nil,
          keyword()
        ) :: :ok | {:error, term()}
  def device_communication_control(destination, state, time_duration, password, opts \\ []) do
    with {:ok, req} <-
           Services.DeviceCommunicationControl.to_apdu(
             %Services.DeviceCommunicationControl{
               state: state,
               time_duration: time_duration,
               password: password
             },
             opts
           ),
         {:ok, %APDU.SimpleACK{}} <- Client.send(stack_client(), destination, req, opts) do
      :ok
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  @doc "Sends Reinitialize Device to a remote BACnet device."
  @spec reinitialize_device(
          destination(),
          BACnet.Protocol.Constants.reinitialized_state(),
          String.t() | nil,
          keyword()
        ) :: :ok | {:error, term()}
  def reinitialize_device(destination, state, password, opts \\ []) do
    case ClientHelper.reinitialize_device(stack_client(), destination, state, password, opts) do
      :ok -> :ok
      other -> normalize_error(other)
    end
  end

  @doc "Sends Time Synchronization (local or UTC) to a remote BACnet device."
  @spec send_time_synchronization(destination(), keyword()) :: :ok | {:error, term()}
  def send_time_synchronization(destination, opts \\ []) do
    case ClientHelper.send_time_synchronization(stack_client(), destination, opts) do
      :ok -> :ok
      other -> normalize_error(other)
    end
  end

  @doc "Reads a chunk from a BACnet File object via Atomic Read File."
  @spec atomic_read_file(
          destination(),
          ObjectIdentifier.t(),
          boolean(),
          integer(),
          non_neg_integer(),
          keyword()
        ) :: {:ok, Services.Ack.AtomicReadFileAck.t()} | {:error, term()}
  def atomic_read_file(
        destination,
        object,
        stream_access,
        start_position,
        requested_count,
        opts \\ []
      ) do
    with {:ok, req} <-
           Services.AtomicReadFile.to_apdu(
             %Services.AtomicReadFile{
               object_identifier: object,
               stream_access: stream_access,
               start_position: start_position,
               requested_count: requested_count
             },
             opts
           ),
         {:ok, %APDU.ComplexACK{} = ack} <- Client.send(stack_client(), destination, req, opts),
         {:ok, response} <- Services.Ack.AtomicReadFileAck.from_apdu(ack) do
      {:ok, response}
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _atomic_read_file} = err -> err
      other -> {:error, other}
    end
  end

  @doc "Writes a chunk to a BACnet File object via Atomic Write File."
  @spec atomic_write_file(
          destination(),
          ObjectIdentifier.t(),
          boolean(),
          integer(),
          binary() | [binary()],
          keyword()
        ) :: {:ok, Services.Ack.AtomicWriteFileAck.t()} | {:error, term()}
  def atomic_write_file(destination, object, stream_access, start_position, data, opts \\ []) do
    with {:ok, req} <-
           Services.AtomicWriteFile.to_apdu(
             %Services.AtomicWriteFile{
               object_identifier: object,
               stream_access: stream_access,
               start_position: start_position,
               data: data
             },
             opts
           ),
         {:ok, %APDU.ComplexACK{} = ack} <- Client.send(stack_client(), destination, req, opts),
         {:ok, response} <- Services.Ack.AtomicWriteFileAck.from_apdu(ack) do
      {:ok, response}
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  @doc "Fetches active alarm summaries from a BACnet device."
  @spec get_alarm_summary(destination(), keyword()) :: read_result
  def get_alarm_summary(destination, opts \\ []) do
    with {:ok, req} <- Services.GetAlarmSummary.to_apdu(%Services.GetAlarmSummary{}, opts),
         {:ok, %APDU.ComplexACK{} = ack} <- Client.send(stack_client(), destination, req, opts),
         {:ok, response} <- Services.Ack.GetAlarmSummaryAck.from_apdu(ack) do
      {:ok, response}
    else
      {:ok, apdu} -> {:error, apdu}
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  defp send_list_element(destination, object, property, elements, service_module, opts) do
    array_index = Keyword.get(opts, :array_index)

    with {:ok, encoded_elements} <- encode_list_elements(List.wrap(elements)),
         {:ok, req} <-
           service_module.to_apdu(
             struct(service_module, %{
               object_identifier: object,
               property_identifier: property,
               property_array_index: array_index,
               elements: encoded_elements
             }),
             opts
           ),
         {:ok, %APDU.SimpleACK{}} <- Client.send(stack_client(), destination, req, opts) do
      :ok
    else
      {:ok, apdu} -> normalize_error({:error, apdu})
      {:error, _destination} = err -> err
      other -> {:error, other}
    end
  end

  defp encode_list_element(%Encoding{} = encoding), do: {:ok, [encoding]}

  defp encode_list_element(%Destination{} = destination) do
    with {:ok, fields} <- Destination.encode(destination) do
      {:ok, Enum.map(fields, &Encoding.create!/1)}
    end
  end

  defp encode_list_element(other), do: {:ok, [Encoding.create!(other)]}

  defp normalize_error({:error, %APDU.Error{} = err}), do: {:error, {:bacnet_error, err}}
  defp normalize_error({:error, %APDU.Reject{} = rej}), do: {:error, {:bacnet_reject, rej}}
  defp normalize_error({:error, %APDU.Abort{} = abort}), do: {:error, {:bacnet_abort, abort}}
  defp normalize_error({:error, _err} = err), do: err
end
