defmodule BacView.BACnet.Subscription do
  @moduledoc """
  Pure helpers for COV subscription records and renewal logic.
  """

  alias BACnet.Protocol.ObjectIdentifier

  @type t :: %{
          device_id: integer(),
          destination: term(),
          object_id: ObjectIdentifier.t(),
          property: atom() | integer(),
          process_id: non_neg_integer(),
          lifetime: non_neg_integer(),
          confirmed: boolean(),
          subscribed_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          last_cov_at: DateTime.t() | nil,
          last_value: term(),
          last_value_formatted: String.t() | nil,
          time_remaining: non_neg_integer() | nil,
          status: :active | :error
        }

  @spec key(integer(), ObjectIdentifier.t(), atom() | integer()) ::
          {integer(), atom(), non_neg_integer(), atom() | integer()}
  def key(device_id, %ObjectIdentifier{type: type, instance: instance}, property) do
    {device_id, type, instance, property}
  end

  @spec object_key(integer(), ObjectIdentifier.t()) :: {integer(), atom(), non_neg_integer()}
  def object_key(device_id, %ObjectIdentifier{type: type, instance: instance}) do
    {device_id, type, instance}
  end

  @spec build(integer(), term(), ObjectIdentifier.t(), atom() | integer(), keyword()) :: t()
  def build(device_id, destination, object_id, property, opts) do
    lifetime = Keyword.get(opts, :lifetime, 3600)
    now = DateTime.utc_now()

    %{
      device_id: device_id,
      destination: destination,
      object_id: object_id,
      property: property,
      process_id: Keyword.fetch!(opts, :process_id),
      lifetime: lifetime,
      confirmed: Keyword.get(opts, :confirmed, false),
      subscribed_at: now,
      expires_at: if(lifetime > 0, do: DateTime.add(now, lifetime, :second), else: nil),
      last_cov_at: nil,
      last_value: nil,
      last_value_formatted: nil,
      time_remaining: nil,
      status: :active
    }
  end

  @doc "Returns true when subscription should be renewed (~80% of lifetime elapsed)."
  @spec needs_renewal?(t(), DateTime.t()) :: boolean()
  def needs_renewal?(%{lifetime: 0}, _now), do: false

  def needs_renewal?(%{expires_at: nil}, _now), do: false

  def needs_renewal?(%{expires_at: expires_at, lifetime: lifetime}, now) do
    remaining = DateTime.diff(expires_at, now, :second)
    threshold = max(30, trunc(lifetime * 0.2))
    remaining <= threshold and remaining > 0
  end

  @spec process_id() :: non_neg_integer()
  def process_id() do
    [node, pid, pid2] =
      self()
      |> :erlang.pid_to_list()
      |> :binary.list_to_bin()
      |> then(&Regex.scan(~r/<(\d+)\.(\d+)\.(\d+)>/, &1))
      |> hd()
      |> tl()
      |> Enum.map(&String.to_integer/1)

    Bitwise.bsl(Bitwise.band(node, 0x0F), 28) + Bitwise.bsl(pid, 13) + pid2
  end
end
