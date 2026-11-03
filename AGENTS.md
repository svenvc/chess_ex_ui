# ChessEx UI

A Phoenix LiveView web interface for playing chess against the pure Elixir
[ChessEx](https://github.com/svenvc/chess_ex) engine. The application is
database-free: in-progress game state lives in the LiveView process, and
completed games are archived as PGN files.

## Project structure

- `lib/chess_ex_ui_web/live/game_live.ex` — the `/` LiveView (also served at `/game`): game state, click handling, engine turns, status, notation and recording.
- `lib/chess_ex_ui/game_archive.ex` — PGN storage: save, list, fetch and validate completed games.
- `lib/chess_ex_ui_web/live/history_live.ex` — `/history`: chronological hall of fame and win/draw statistics.
- `lib/chess_ex_ui_web/live/game_view_live.ex` — `/history/:id`: read-only PGN replay.
- `lib/chess_ex_ui_web/controllers/game_download_controller.ex` — `/history/:id/download`: PGN download.
- `lib/chess_ex_ui_web/game_format.ex` — shared date, duration and result formatting.
- `lib/chess_ex_ui_web/components/chess_board.ex` — presentational board component; sends a single `square_click` event unless `interactive` is false.
- `lib/chess_ex_ui_web/chess_assets.ex` — board/piece asset lookup. Change the module attributes here to swap themes.
- `lib/chess_ex_ui_web/components/layouts.ex` — application shell. The `bare` option renders only page content; `scroll` lets a bare page grow and scroll. Both the game and the history pages use bare; history also uses `scroll`.
- `priv/static/images/boards/blue.png` and `priv/static/images/pieces/gioco/*.svg` — vendored lichess assets.
- `ASSETS.md` — provenance and licenses of the vendored assets.
- `TODO.md` — completed first-pass work and the follow-up backlog.

## Running and testing

- The `chess_ex` dependency is a path dependency to `../chess_ex`; check it out next to this repository.
- `mix setup` — fetch dependencies and install/build assets.
- `mix phx.server` — start the development server; the board is at `/` (`/game` is an alias).
- `mix assets.build` — rebuild Tailwind and esbuild after class or CSS changes.
- `mix precommit` — compile with warnings as errors, format, and run tests. Run it before finishing a change.

## Scripted play (black-box driver)

`scripts/play_remote.mjs` drives a running instance through a real browser: it
clicks `#square-*` elements, reads the published state attributes and plays
until the game has a result. It needs no application support beyond the markup
below, and it never calls a private endpoint.

The markup is a contract. Renaming or dropping these breaks the driver:

| Selector                          | Meaning                                        |
| --------------------------------- | ---------------------------------------------- |
| `#square-a1` … `#square-h8`       | one button per square, `phx-value-square`      |
| `#board[data-fen]`                | full FEN of the position on the board          |
| `#board[data-side-to-move]`       | `white` / `black`                              |
| `#board[data-ply]`                | number of moves played                         |
| `#board[data-orientation]`        | `white` / `black`                              |
| `#board[data-busy]`               | `true` while the engine is thinking            |
| `#turn-indicator[data-thinking]`  | `true` / `false`                               |
| `#status[data-game-over]`         | `true` once the game has a result              |
| `#result[data-result]`            | `*`, `1-0`, `0-1` or `1/2-1/2`                 |
| `#recorded-game[data-game-id]`    | id of the archived PGN, once it is written     |
| `#new-game`, `#switch-sides`, `#resign` | the game controls                        |

Rules for the driver: read the position from `data-fen` rather than from
`aria-label` text (labels add `, in check` for a king in check), derive legal
destinations from the `[data-target="true"]` squares the board highlights rather
than duplicating move generation, and wait on `data-busy` / `data-ply` instead
of sleeping. A finished game is archived permanently in `/history`, so the
script refuses any host other than localhost unless `ALLOW_REMOTE=1` is set.

Two modes: a self-contained demo game, and a session for playing externally
(`--serve`, then `--state` / `--step e2e4` / `--close`). The session is needed
because the game lives in one LiveView process, so it holds one browser tab and
exposes it over `127.0.0.1` with a token in `tmp/play_session.json`. Never widen
that listener beyond loopback.

Against the deployed instance, name the host and lift the guard explicitly:

```sh
ALLOW_REMOTE=1 node scripts/play_remote.mjs --url https://chess.stfx.eu --serve
```

That game is archived in the public `/history` for everyone, so run it only as a
deliberate one-off — not on a schedule, not in a loop, and not as part of `mix
precommit` or any other routine check.

## Chess UI rules

- Derive selectable destinations from `Chess.Rules.legal_moves/1`; do not duplicate move generation in the UI.
- Before applying a human move, check it with `Chess.Rules.legal_move?/2` and apply it with `Chess.Rules.apply/2`. Engine moves come from `ChessUI.Engine`.
- Run engine searches with `start_async/3`, never in the LiveView process; cancel them with `cancel_async/3` on new game, side switch and resignation. The `:turn` token invalidates stale results.
- While `thinking` is true the board rejects clicks; the turn indicator shows the thinking state.
- `Chess.Game.moves` is newest first. Use `Chess.Game.moves_in_order/1` for display and `Chess.Game.replay/1` + `Chess.SAN.to_san/2` for notation.
- Use `Chess.Narrator` for the status line and the last-move description rather than duplicating its wording.
- Pawn promotion is auto-queen in the current UI. A promotion picker is planned.
- In-progress game state is intentionally in the LiveView only; a refresh starts a new game. Completed games are recorded; do not add in-progress persistence without a decision.
- The engine plays a 4-ply `Chess.Search` with the opening book, configured in
  `config/config.exs` through `ChessUI.Engine`.

## REST API

- `/api` is anonymous and in-memory. `ChessUI.Api.GameStore` owns the games;
  keep the full `Chess.Game` because a FEN alone cannot represent repetition
  history.
- `POST /api/games` creates a game; `GET /api/games/:id` returns the FEN;
  `POST /api/games/:id/move` plays a SAN/UCI move or, with an empty body, the
  engine's move. `GET /api` is the plain-text description.
- Enforce the turn guard: a move body is only for `player_color`, an empty body
  only for the other side. This makes retries safe.
- Illegal or ambiguous moves are `422`, a wrong turn or a finished game `409`,
  an unknown or expired game `404`, rate limits `429`, capacity or engine
  failure `503`, an engine timeout `504`. Do not use `5xx` for client mistakes.
- Keep engine searches out of `GameStore`: reserve with `begin_engine/1`,
  search through `ChessUI.Api.TaskSupervisor`, and finish with
  `finish_engine/2`.
- Archive only finished games, once, through `ChessUI.GameArchive` with
  `player_name: "API"` and `event: "Chess Ex API Game"`. Never archive
  abandoned or expired games.
- Bound resources: per-address creation/move/read rate limits, per-address and
  global game caps, idle TTL, hard maximum age and engine concurrency. The
  values live in `ChessUI.Api.Config`.
- API tests are `async: false`; reset `GameStore` and `RateLimit` in setup and
  restore any `Application.put_env` changes.
- API errors are `text/plain`, never Phoenix HTML. `ChessUIWeb.Plugs.ApiFormat`
  selects the `text` error view, `ChessUIWeb.Plugs.Parsers` answers malformed
  bodies and query strings, and `ChessUIWeb.Api.ErrorController` catches
  unknown paths and wrong methods. Keep new API routes before those catch-alls.
- The API is plain text only. JSON request bodies are rejected with `415`;
  do not add JSON input or JSON responses.
- The rate limiter keys on `conn.remote_ip`. Forwarded-header rewriting is
  opt-in at runtime through `CHESS_EX_UI_PROXY_REWRITE_ON` and
  `ChessUIWeb.Plugs.ProxyRewrite`; never trust forwarded headers unless the
  proxy strips or overwrites them. Caddy at the edge sets `X-Forwarded-For` to
  the immediate client and ignores client-supplied values by default.

## Game records

- Record only games with a result: checkmate, stalemate, the automatic draw rules and resignation. New game, switching sides, closing the page and engine failures must not write a record.
- `ChessUI.GameArchive` owns the PGN format and the games directory. Do not hand-roll a second PGN writer; use `Chess.PGN`.
- One PGN per game, named `<uuid>.pgn`, written atomically through a temporary file. The `GameId` header holds the same id.
- Include the seven tag roster plus start/end time, duration, termination reason, player colors, engine options, app version and final FEN. Never store visitor identity, IP addresses or session data.
- The games directory is `:games_dir` (default `var/games`, override with `CHESS_EX_UI_GAMES_DIR`). History reads it on demand; there is no index or database.
- Validate a game id with `ChessUI.GameArchive.id?/1` before building a path. Skip unreadable or corrupt PGNs in listings instead of crashing.
- The game page links to the saved record after a result. `/history` is chronological, newest first; `/history/:id` replays a PGN read-only.
- `ChessUIWeb.ChessBoard` takes `interactive={false}` on replay pages so it does not emit `square_click` events.

## Game page layout

- `/` uses `<Layouts.app flash={@flash} bare>`: no app header, branding or theme toggle.
- The page must fit in one viewport without page scrolling. The board is capped by both width and `100dvh`; the side panels scroll internally if needed.
- Keep the turn indicator next to the New game / Switch sides / Resign controls.
- File labels are below the board and rank labels to the left; both reverse with orientation.
- Use `ChessUIWeb.ChessBoard` for board markup; do not hand-roll a second board.
- The board marks the king in check with a red glow, derived from `Chess.Rules.in_check?/1` and `Chess.Board.king/2`; never re-implement attack detection.
- The board uses the lichess `blue` texture and `gioco` pieces. Alternatives are selected through `ChessUIWeb.ChessAssets`.

## Assets and licensing

- Vendor lichess assets; do not hotlink them.
- `public/images/board/blue.png` is AGPLv3+ (lila authors and pirouetti).
- `public/piece/gioco/*.svg` are CC BY-NC-SA 4.0 (sadsnake1).
- Add attribution to `ASSETS.md` when adding a board or piece set.

## General project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


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

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

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
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
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
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
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

In the template, the form form assign can be passed to the `<.form>` function component:

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
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->