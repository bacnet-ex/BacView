defmodule BacViewWeb.GettextLC do
  @moduledoc false

  @doc """
  Locale-aware gettext for HEEx templates.

  References `@locale` and `@locale_version` so LiveView change tracking
  re-renders translated strings when the language changes.
  """
  defmacro __using__(_opts) do
    quote do
      import BacViewWeb.GettextLC
    end
  end

  defmacro gettext(msgid) do
    quote do
      BacViewWeb.GettextLC.translate!(
        unquote(msgid),
        %{},
        Map.get(var!(assigns), :locale),
        Map.get(var!(assigns), :locale_version, 0)
      )
    end
  end

  defmacro gettext(msgid, bindings) do
    quote do
      BacViewWeb.GettextLC.translate!(
        unquote(msgid),
        unquote(bindings),
        Map.get(var!(assigns), :locale),
        Map.get(var!(assigns), :locale_version, 0)
      )
    end
  end

  @type bindings :: map() | keyword()

  @doc """
  Locale-aware translation for LiveView templates.

  Reference `@locale` and `@locale_version` at the call site so change
  tracking re-renders strings when the language changes.
  """
  @spec t(String.t() | nil, integer(), String.t(), bindings()) :: String.t()
  def t(locale, locale_version, msgid, bindings \\ %{})

  def t(locale, locale_version, msgid, bindings) do
    translate!(msgid, bindings, locale, locale_version)
  end

  @spec translate!(String.t(), bindings(), String.t() | nil, integer()) :: String.t()
  def translate!(msgid, bindings, locale, locale_version) do
    _track = {locale, locale_version}
    locale = locale || Gettext.get_locale(BacViewWeb.Gettext) || "de"
    bindings = normalize_bindings(bindings)

    Gettext.with_locale(BacViewWeb.Gettext, locale, fn ->
      if bindings == %{} do
        Gettext.dgettext(BacViewWeb.Gettext, "default", msgid)
      else
        Gettext.dgettext(BacViewWeb.Gettext, "default", msgid, bindings)
      end
    end)
  end

  defp normalize_bindings(bindings) when is_map(bindings), do: bindings

  defp normalize_bindings(bindings) when is_list(bindings) do
    Enum.into(bindings, %{})
  end
end
