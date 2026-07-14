# BacView — agent guidelines

BacView is a **BACnet explorer** built with **Phoenix LiveView** and [bacstack](https://github.com/bacnet-ex/bacstack). App modules are `BacView` / `BacViewWeb`.

Primary UI routes (see `lib/bac_view_web/router.ex`):

| Path | LiveView |
|------|----------|
| `/` | `DashboardLive` |
| `/devices/:device_id` | `DeviceLive` |
| `/devices/:device_id/objects/:type/:instance` | `ObjectLive` |

There is **no user auth / `current_scope`** in this app. Do not invent scope plugs or pass `current_scope` to layouts unless that feature is intentionally added.

---

## Project guidelines

- Use `mix precommit` when you are done with a set of changes and fix all issues it reports. It runs (see `mix.exs`):

      deps.unlock --unused
      compile --warnings-as-errors
      format --check-formatted
      credo --strict --all
      dialyzer
      test --warnings-as-errors

- Use the included **`:req` (`Req`)** library for HTTP. **Avoid** `:httpoison`, `:tesla`, and `:httpc`.
- Prefer **existing modules** over new layers. Domain BACnet logic lives under `lib/bac_view/bacnet/`; UI under `lib/bac_view_web/`.
- Do **not** add Ecto schemas/repos for BACnet domain data unless explicitly requested. Runtime state uses **ETS** (see `BacView.BACnet.Cache`) and JSON settings (`BacView.Settings` / `runtime_settings.json`).
- Prefer mechanical, behavior-preserving refactors over “clever” rewrites of the BACnet stack.

### Localization (DE/EN)

- UI copy uses **German msgids** via `t(@locale, @locale_version, "...")` in templates and `gt("...")` / `gt("...", opts)` in LiveView modules and helpers.
- English catalog: `priv/gettext/en/LC_MESSAGES/default.po`
- When you **add or change** translatable UI strings:
  1. Update the `TRANSLATIONS` map in `priv/gettext/build_en_translations.py`
  2. **Always** regenerate the catalog yourself (do not ask the user to run it):

         python3 priv/gettext/build_en_translations.py

  3. Run `mix test test/bac_view_web/locale_test.exs test/bac_view_web/locale_switch_live_test.exs` (or `mix precommit`)
- The script **fails** if any msgid lacks an English translation — add the missing entry before finishing.
- Locale switch: `BacViewWeb.LocaleHook` on the default `live_session`; use `LocaleAttrs` in function components that need `t/3`.

### Config & environment

Important keys (see `config/config.exs`, `config/runtime.exs`, `README.md`):

| Key / env | Role |
|-----------|------|
| `BACVIEW_DESKTOP=1` | **Compile-time** desktop build (`elixir-desktop`); `mix clean` when switching web ↔ desktop |
| `BACVIEW_TIMEZONE` | IANA timezone (default `Europe/Zurich`) |
| `BACVIEW_PROPERTY_READ_CONCURRENCY` | Max parallel individual `ReadProperty` (default **8**). Set **1** if old devices are overwhelmed |
| `BACVIEW_SETTINGS_PATH` | Override path for persisted stack settings |
| `BACVIEW_BACSTACK_DEBUG` | Verbose bacstack logging |
| `BACVIEW_ENABLE_MSTP` | Force MS/TP enable when UART stack is available |
| `:bacview, :property_read_concurrency` | Application env used by `PropertyReader.property_read_concurrency/0` |

---

## BacView architecture (BACnet)

### Layers

| Layer | Location | Responsibility |
|-------|----------|----------------|
| Stack / transport | `BacView.BACnet.Stack`, `Transport`, `Client` | bacstack client, UDP/MS/TP, BBMD / foreign registration |
| Discovery | `Discovery`, `IAmCollector` | Who-Is / I-Am, device list ETS |
| Per-device session | `DeviceSession` (+ supervisor) | Load/scan device, object cache, property reads/writes |
| Property IO | `PropertyLoad`, `PropertyReader`, `ObjectScanRead` | Full object property load, RPM vs individual, scan fallback |
| Validation recovery | `ValidationSkipStore` | Persist skip modes after scan recovery |
| Subscriptions / COV | `SubscriptionManager` | COV subscribe, notification log, pruning |
| Alarms | `AlarmEvent`, `ActiveAlarms` | Event state, active-alarm lists/counts |
| Hierarchy | `HierarchyBuilder`, `NameHierarchyBuilder`, `HierarchySplit` | Structured View + name-split trees |
| Web | `BacViewWeb.Live.*`, components | LiveViews, tables, popups, charts |

### ETS tables (`BacView.BACnet.Cache`)

Named tables include: `:bacview_devices`, `:bacview_objects`, `:bacview_properties`, `:bacview_subscriptions`, `:bacview_hierarchy`, `:bacview_name_hierarchy`, `:bacview_events`, `:bacview_validation_skip_modes`.

- **Web code must not** open subscription ETS directly — use `SubscriptionManager.list_active/0` (and related APIs).
- Tests that touch named tables should use `BacView.Test.BacnetEtsLock.with_tables/2` when concurrent tests share global ETS.

### Device load vs object property load

**Full device scan** (`DeviceSession` load/reload):

- Stages: reading device → object list → **scanning objects** → hierarchy.
- Progress: PubSub `"device:#{id}:load_progress"` → `{:device_load_progress, progress}` (object-level done/total). UI: `DeviceLoadProgress`.

**Single-object properties** (`DeviceSession.read_properties` → `PropertyLoad` → `PropertyReader`):

1. Prefer **RPM** (`read_object` / property multiple) with opts from `PropertyLoad.property_read_opts/2`.
2. On segmentation/buffer-style failures → individual path (property list / schema + concurrent `ReadProperty`).
3. **Skip mode** (scan recovery) is applied via `object_opts: [skip_property_validation_remote_object: …]` on the normal path — do **not** force the scan path only because skip mode is set.
4. On certain hard failures (`properties_scan_fallback_on_error?/1`) → `ObjectScanRead` (thin wrapper around `PropertyReader.read_properties_map/4`).

**Individual (one-by-one) property progress** (object properties view):

- `PropertyReader` accepts `on_property_progress: fun/1` with  
  `%{stage: :reading_properties, done: n, total: m}`.
- `DeviceSession` broadcasts by default on  
  `"device:#{id}:properties_progress"` →  
  `{:object_properties_progress, object_id, progress}`.
- `ObjectLive` subscribes and drives `@properties_progress` in `ObjectDetail` (banner + bar). Clear progress when load finishes.
- **Do not** send progress callbacks into bacstack client opts; strip via `client_opts/1` (never pass `:on_property_progress` to bacstack).

### Validation skip store

`BacView.BACnet.ValidationSkipStore` owns durable skip modes (`:value` | `true` for bacstack):

- Resolve order: session object tags → `device.objects` tags → ETS.
- `put/3` **must** persist (ensures ETS table); do not silently no-op.
- Full device rescan **clears** skip modes for that device.
- LiveViews should **not** pre-resolve skip mode for normal reads; session resolve is enough.

### Property list fallbacks

- Full `property_list` array fails → indexed 0..N **only** when `Segmentation.array_fallback_error?/1` (segmentation/buffer **or** `:property_not_readable`).
- `:unknown_property` on `property_list` → **schema** path (device has no list), **not** indexed N-reads.
- Heavy device properties (`object_list`, bindings, COV lists, etc.) are skipped on individual loads — see `PropertyReader.heavy_properties_for/1`.

### Concurrency

- Default parallel individual `ReadProperty`: **8** (`:property_read_concurrency` / `BACVIEW_PROPERTY_READ_CONCURRENCY`).
- Device object scan still uses separate higher concurrency for **objects** (`Task.async_stream` in `DeviceSession.scan_object_list`), not the property-read setting.
- Do not hard-code concurrency `1` globally; use config for fragile sites.

### UI structure conventions

- LiveViews: `DashboardLive`, `DeviceLive`, `ObjectLive` under `lib/bac_view_web/live/`.
- Prefer **extracted helpers** over growing LiveViews further (`DeviceUrl`, `*Assigns`, `ChartEventPayload`, `CovNotificationChartLive`, badge/count modules). `DeviceLive` / `ObjectLive` are already very large — extract rather than add bulk.
- Charts: shared JS hook `TrendLogChart` + `ChartEventPayload`; COV chart lifecycle via `CovNotificationChartLive`.
- Icons: **always** `<.icon name="hero-…">` from `CoreComponents`, never Heroicons modules.
- CSS: Tailwind v4 + custom `bac-*` classes in `assets/css/app.css`. daisyUI is vendored for theme tokens — **prefer existing BacView components and `bac-*` utilities**; do not expand daisyUI component-driven UI as the primary design system.
- Keep `@import "tailwindcss" source(none)` and `@source` paths covering `lib/bac_view_web` (see `app.css`).

### Testing

- Prefer `element/2`, `has_element/2`, stable DOM **ids** over brittle full-page text.
- BACnet unit tests often use fake **client modules** (function-exported `read_object` / `read_property`) rather than real UDP.
- After localization changes, always run locale tests or full `mix precommit`.
- Do not leave the suite red for flaky env pollution (e.g. transport port tests); fix isolation if you touch that area.

### Desktop (optional)

- Compile with `BACVIEW_DESKTOP=1` (`mix desktop.server`, `mix desktop_installer`).
- Web workflow remains the default. See README for wx/desktop requirements.

---

### Phoenix v1.8 guidelines (BacView)

- **Always** begin LiveView templates with `<Layouts.app flash={@flash} ...>` wrapping content.
- `BacViewWeb.Layouts` is aliased via `BacViewWeb` html helpers — no extra alias needed.
- **Do not** call `<.flash_group>` outside `layouts.ex` (Phoenix 1.8 placement).
- **Always** use `<.icon name="hero-…">` and `<.input>` from `core_components.ex` when available.
- If you override `<.input class="...">`, you replace defaults entirely — supply full styling.

### JS and CSS guidelines

- Prefer Tailwind utilities + existing `bac-*` CSS for polished, responsive UI.
- Tailwind v4 import pattern in `app.css` (keep `@source` for css/js/`lib/bac_view_web`).
- **Never** use `@apply` in raw CSS.
- Only **app.js** and **app.css** bundles are supported — import vendors into those; **no** external script/link in layouts; **no** inline `<script>` in HEEx.
- Hooks that own DOM: `phx-hook` **and** `phx-update="ignore"`.

### UI/UX guidelines

- Prioritize usability, clear hierarchy, spacing, and readable typography.
- Subtle transitions/hover states; loading and empty states should be explicit (device load banner, object property progress, etc.).

---

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", BacViewWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `BacViewWeb.Admin.UserLive` module

- Default browser scope is already aliased with `BacViewWeb` — route with `live "/", DashboardLive`, etc.
- `Phoenix.View` is no longer needed or included with Phoenix; don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For app-wide template imports, use `lib/bac_view_web.ex` `html_helpers` so they are available to LiveViews and modules that `use BacViewWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `BacViewWeb.DeviceLive`, with a `Live` suffix. Default `:browser` scope is aliased with `BacViewWeb`, so routes are `live "/devices/:device_id", DeviceLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** test against raw HTML dumps as the primary assertion style; **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module (map params or changeset-backed)
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
