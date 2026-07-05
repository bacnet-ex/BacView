defmodule BacViewWeb.LocaleHookTest do
  use ExUnit.Case, async: true

  alias BacViewWeb.LocaleHook

  test "uses BacView Gettext default locale when session and connect params are empty" do
    assert LocaleHook.resolve_locale(%{}, %{}, default_locale: "en") == "en"
    assert LocaleHook.resolve_locale(%{}, %{}, default_locale: "de") == "de"
  end

  test "prefers connect params over configured default locale" do
    assert LocaleHook.resolve_locale(%{"locale" => "en"}, %{}, default_locale: "de") == "en"
  end
end
