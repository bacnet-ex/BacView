defmodule BacView.BACnet.HierarchyNode do
  @moduledoc """
  A node in a Structured View hierarchy tree.
  """

  alias BACnet.Protocol.ObjectIdentifier

  @folder_type :name_folder

  @type t :: %__MODULE__{
          object_id: ObjectIdentifier.t(),
          type: atom(),
          instance: non_neg_integer(),
          name: String.t() | nil,
          annotation: String.t() | nil,
          type_label: String.t(),
          node_type: atom() | nil,
          node_subtype: String.t() | nil,
          children: [t()],
          child_count: non_neg_integer(),
          cycle: boolean()
        }

  defstruct [
    :object_id,
    :type,
    :instance,
    :name,
    :annotation,
    :type_label,
    :node_type,
    :node_subtype,
    children: [],
    child_count: 0,
    cycle: false
  ]

  @spec id(t()) :: String.t()
  def id(%__MODULE__{type: type, instance: instance}), do: "#{type}:#{instance}"

  @spec folder_type() :: :name_folder
  def folder_type(), do: @folder_type

  @spec folder?(t() | map()) :: boolean()
  def folder?(%__MODULE__{type: type}), do: type in [:structured_view, @folder_type]
  def folder?(_node), do: false
end
