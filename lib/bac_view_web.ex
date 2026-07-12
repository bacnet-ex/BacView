defmodule BacViewWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use BacViewWeb, :controller
      use BacViewWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths(), do: ~w(assets fonts images favicon.ico robots.txt icon.png)

  def router() do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel() do
    quote do
      use Phoenix.Channel
    end
  end

  def controller() do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: BacViewWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view() do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component() do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html() do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      import BacViewWeb.CoreComponents
      import Gettext, only: [dgettext: 3, dgettext: 4, dngettext: 6]

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      alias BacViewWeb.Layouts
      alias Phoenix.LiveView.JS

      unquote(verified_routes())
      import BacViewWeb.GettextLC, only: [t: 3, t: 4]
    end
  end

  defp html_helpers() do
    quote do
      # Translation: t/3 in LiveView templates, gt/1 in callbacks
      import Gettext, only: [dgettext: 3, dgettext: 4, dngettext: 6]
      import BacViewWeb.GettextBackend, only: [gt: 1, gt: 2]
      import BacViewWeb.GettextLC, only: [t: 3, t: 4]

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import BacViewWeb.CoreComponents

      # Common modules used in templates
      alias BacViewWeb.Layouts
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes() do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: BacViewWeb.Endpoint,
        router: BacViewWeb.Router,
        statics: BacViewWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
