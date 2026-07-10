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
          cov_increment: float() | nil,
          subscribe_service: :subscribe_cov_property | :subscribe_cov,
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
      cov_increment: Keyword.get(opts, :cov_increment),
      subscribe_service: Keyword.get(opts, :subscribe_service, :subscribe_cov_property),
      subscribed_at: now,
      expires_at: if(lifetime > 0, do: DateTime.add(now, lifetime, :second), else: nil),
      last_cov_at: nil,
      last_value: nil,
      last_value_formatted: nil,
      time_remaining: nil,
      status: :active
    }
  end

  @min_renew_interval_ms 5_000
  @max_renew_interval_ms 45_000

  @doc "Seconds remaining at which a subscription should be renewed (~80% of lifetime elapsed)."
  @spec renewal_threshold(non_neg_integer()) :: pos_integer()
  def renewal_threshold(lifetime) when lifetime > 0, do: max(30, trunc(lifetime * 0.2))
  def renewal_threshold(_lifetime), do: 30

  @doc """
  Renewal check interval derived from lifetime.

  Runs several times within the renewal window so short lifetimes are not missed.
  """
  @spec renew_check_interval_ms(non_neg_integer()) :: pos_integer()
  def renew_check_interval_ms(lifetime) when lifetime > 0 do
    threshold_ms = renewal_threshold(lifetime) * 1_000
    interval = div(threshold_ms, 3)

    max(@min_renew_interval_ms, min(@max_renew_interval_ms, interval))
  end

  def renew_check_interval_ms(_lifetime), do: @max_renew_interval_ms

  @doc "Returns true when subscription should be renewed (~80% of lifetime elapsed)."
  @spec needs_renewal?(t(), DateTime.t()) :: boolean()
  def needs_renewal?(%{lifetime: 0}, _now), do: false

  def needs_renewal?(%{lifetime: lifetime, expires_at: nil}, _now) when lifetime > 0, do: false

  def needs_renewal?(%{lifetime: lifetime} = sub, now) when lifetime > 0 do
    case effective_remaining(sub, now) do
      remaining when is_integer(remaining) -> remaining <= renewal_threshold(lifetime)
      _remaining -> false
    end
  end

  @spec effective_remaining(t(), DateTime.t()) :: integer() | nil
  def effective_remaining(%{expires_at: %DateTime{} = expires_at}, now),
    do: DateTime.diff(expires_at, now, :second)

  def effective_remaining(_sub, _now), do: nil

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
