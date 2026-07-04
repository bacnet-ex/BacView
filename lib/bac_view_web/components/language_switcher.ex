defmodule BacViewWeb.LanguageSwitcher do
  @moduledoc false
  use BacViewWeb, :html

  attr(:locale, :string, required: true)
  attr(:locale_version, :integer, default: 0)

  def language_switcher(assigns) do
    ~H"""
    <div
      class="flex items-center gap-0.5 p-0.5 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-bg-elevated)]"
      role="group"
      aria-label={t(@locale, @locale_version, "Sprache wechseln")}
    >
      <button
        type="button"
        phx-click="set_locale"
        phx-value-locale="de"
        class={[
          "bac-btn bac-btn-xs",
          @locale == "de" && "bac-btn-primary" || "bac-btn-ghost"
        ]}
      >
        DE
      </button>
      <button
        type="button"
        phx-click="set_locale"
        phx-value-locale="en"
        class={[
          "bac-btn bac-btn-xs",
          @locale == "en" && "bac-btn-primary" || "bac-btn-ghost"
        ]}
      >
        EN
      </button>
    </div>
    """
  end
end
