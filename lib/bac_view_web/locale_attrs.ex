defmodule BacViewWeb.LocaleAttrs do
  @moduledoc false

  @doc """
  Standard locale attributes for function components.
  """
  defmacro __using__(_opts) do
    quote do
      attr(:locale, :string, default: "de")
      attr(:locale_version, :integer, default: 0)
    end
  end
end
