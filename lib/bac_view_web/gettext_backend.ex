defmodule BacViewWeb.GettextBackend do
  @moduledoc false

  @doc """
  Runtime gettext for LiveView callbacks and private helpers.

  Template code should use the locale-aware `gettext` macro from
  `BacViewWeb.GettextLC` instead.
  """
  def gt(msgid) do
    Gettext.dgettext(BacViewWeb.Gettext, "default", msgid)
  end

  def gt(msgid, bindings) do
    Gettext.dgettext(BacViewWeb.Gettext, "default", msgid, bindings)
  end
end
