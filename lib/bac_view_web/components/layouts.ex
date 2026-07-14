defmodule BacViewWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BacViewWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates("layouts/*")

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)
  attr(:show_shortcuts, :boolean, default: false)
  attr(:shortcuts_context, :atom, default: :dashboard)

  slot(:inner_block, required: true)
  slot(:topbar_end)

  def app(assigns) do
    ~H"""
    <%= for _ <- [@locale_version] do %>
      <div
        id={"bacview-root-#{@locale_version}"}
        phx-hook="BacViewRoot"
        class="bac-app"
        data-theme="dark"
        data-locale={@locale}
        data-locale-version={@locale_version}
      >
      <div class="bac-app-bg" aria-hidden="true"></div>

      <header class="bac-topbar">
        <.link navigate={~p"/"} class="bac-logo">
          <span class="bac-logo-mark">
            <.icon name="hero-signal" class="size-4" />
          </span>
          <span>BacView</span>
        </.link>

        <div class="flex-1" />

        <div class="flex items-center gap-2 overflow-visible">
          {render_slot(@topbar_end)}
          <button
            type="button"
            phx-click="toggle_shortcuts"
            class="bac-btn bac-btn-ghost bac-btn-xs"
            title={t(@locale, @locale_version, "Tastaturkürzel")}
          >
            <.icon name="hero-command-line" class="size-3.5" />
            <span class="hidden sm:inline">{t(@locale, @locale_version, "Hilfe")}</span>
          </button>
          <BacViewWeb.LanguageSwitcher.language_switcher
            locale={@locale}
            locale_version={@locale_version}
          />
        </div>
      </header>

      <main class="bac-main">
        {render_slot(@inner_block)}
      </main>

      <BacViewWeb.KeyboardShortcuts.keyboard_shortcuts
        show={@show_shortcuts}
        context={@shortcuts_context}
        locale={@locale}
        locale_version={@locale_version}
      />
      </div>

      <.flash_group flash={@flash} locale={@locale} locale_version={@locale_version} />
    <% end %>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")
  attr(:id, :string, default: "flash-group", doc: "the optional id of flash container")
  attr(:locale, :string, default: "de")
  attr(:locale_version, :integer, default: 0)

  def flash_group(assigns) do
    ~H"""
    <%= for _ <- [@locale_version] do %>
    <div id={@id} class="bac-toast" aria-live="polite">
      <.flash kind={:info} flash={@flash} locale={@locale} locale_version={@locale_version} />
      <.flash kind={:error} flash={@flash} locale={@locale} locale_version={@locale_version} />

      <.flash
        id="connection-error"
        kind={:error}
        locale={@locale}
        locale_version={@locale_version}
        title={t(@locale, @locale_version, "Verbindung zum Server nicht möglich")}
        phx-disconnected={show("#connection-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#connection-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        <span class="inline-flex items-center gap-1">
          {t(@locale, @locale_version, "Verbindung wird wiederhergestellt…")}
          <.icon name="hero-arrow-path" class="size-3 motion-safe:animate-spin" />
        </span>
      </.flash>
    </div>
    <% end %>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 p-0.5 rounded-lg border border-[var(--bac-border)] bg-[var(--bac-bg-elevated)]">
      <button
        class="bac-btn bac-btn-icon bac-btn-ghost"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title={t(@locale, @locale_version, "System")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="bac-btn bac-btn-icon bac-btn-ghost"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title={t(@locale, @locale_version, "Hell")}
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="bac-btn bac-btn-icon bac-btn-ghost"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title={t(@locale, @locale_version, "Dunkel")}
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
