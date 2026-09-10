# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`omaseek` — a web search overlay with vim keybindings, packaged as an
**Omarchy 4 plugin**. It is not a standalone app: `manifest.json` declares an
`overlay` entry point (`src/Search.qml`) that is loaded *in-process* by the
running `omarchy-shell` Quickshell instance. There is no build step, no package
manager, and no dependencies — Python is stdlib-only and the JS is plain ES
modules run by node's own test runner.

## Commands

```bash
./bin/test                              # all unit tests (node --test, no shell, no network)
node --test test/motions.test.mjs       # one file
node --test --test-name-pattern 'iw'    # one test by name

./bin/search "python asyncio" | jq      # exercise the backend on its own
./bin/search --next "$(./bin/search rust | jq -c .next)" | jq   # page 2
./bin/ask --agents | jq                 # which agent CLIs are installed, and the default
./bin/ask --json '{"question":"…"}'     # one chat turn through the configured agent

./bin/dev-watch                      # hot reload while editing (Ctrl-C to stop)
omarchy-shell shell rescanPlugins       # manual reload
omarchy-restart-shell                   # needed when a keepLoaded component is already instantiated
quickshell log -p /usr/share/omarchy/shell -f   # QML errors and console.log (not journald)
```

Run `./bin/test` after touching anything in `src/lib`. There is no linter.

## Architecture

### The pure/impure split

One rule governs the layout: **anything that is a pure function of its inputs
lives in `src/lib` as an `.mjs` ES module; everything that needs Qt stays in
QML.** The same file loads in both (`import "../lib/motions.mjs" as Motions` in
QML, `import` in node), so cursor arithmetic, escape-sequence matching, page
merging and config parsing are all under test without a compositor.

- `src/lib/motions.mjs` — cursor motions (`w b e f t 0 ^ $`), `(text, pos) -> pos`
- `src/lib/textobjects.mjs` — `iw aw i" a(` … `(text, pos) -> {start, end}`
- `src/lib/keymap.mjs` — the insert-mode escape sequence (`jk`) and its config
- `src/lib/search.mjs` — result normalising, de-duplication, status/error strings
- `src/lib/settings.mjs` — config text → settings, and the settings-page row list
- `src/lib/markdown.mjs` — the agent's Markdown → the rich-text subset a TextEdit colours; the transcript layout
- `src/lib/keys.mjs` — chord → command name for the reading panes, and the `gg`/`gv` prefix machine

`VimTextField.qml` is therefore only a mode machine and key dispatch — if you
add a motion or an object, the logic goes in `src/lib` with tests and the QML
gains a dispatch case.

**QML's JS engine is not node.** `.mjs` modules must stay within the subset both
understand: `Object.hasOwn` exists in node and not in QML, so a guard using it
passes every test and throws on the first keystroke in the shell. Prefer plain
lookups, indexed loops and `indexOf` over recent built-ins; a test pass is not
proof the code runs in the panel.

### QML ↔ backend contract

`bin/search` is a separate process on purpose, and speaks one backend: a
**SearXNG instance the user runs themselves** (`searxng_url`, default
`http://localhost:8888`). Querying your own service raises none of the
terms-of-service problems the old DuckDuckGo scraper did — that backend and the
Exa fallback were removed deliberately, so do not reintroduce scraping,
browser-UA spoofing, or a third-party search API without being asked.

It always prints one JSON object — `{ok: true, results, next, backend}` or
`{ok: false, error, message}` — and exits 0 even on a handled failure. Errors
are typed (`network`/`http`/`usage`), and a failure carries `setup: true` for
the one case a person can fix from the panel: the instance is not running.
`Search.qml` turns that into the SetupPrompt view, which explains Docker and
asks, rather than showing an error the user cannot act on. A 403 is *not*
marked `setup` — SearXNG ships `formats: [html]`, so the JSON API is off until
`settings.yml` enables it, and the error message names that fix.

**Speed**: one request per page is the budget. `emit_page` fills the buffer to
exactly the page — an earlier lookahead row cost a whole extra request whenever
a SearXNG page came back exactly `PAGE_SIZE` long, doubling latency on a
keypress. Everything else is SearXNG waiting on upstream engines — and it
waits for every engine in the category, so `searxng_engines` in config.json
(hand-edited, passed through as `engines=`) is the big lever: naming the ones
that answer took a query from ~1.1 s to ~0.3 s locally. `outgoing.request_timeout`
in its `settings.yml` is the backstop.

Pages are sliced from a session buffer under `~/.cache/omaseek/` rather
than served straight from SearXNG, because a SearXNG page is however many
engines answered in time. Rows are de-duplicated on URL *and* domain+title, in
`absorb()` and again in `search.mjs`.

### bin/ask — the AI half

Same shape as `bin/search`: a separate stdlib-Python process, one JSON object
out, exit 0 on handled failure. It speaks to **agent CLIs already installed**
(`claude`, `codex`, `opencode`, `gemini`, `hermes`, `copilot`, `cursor-agent`)
through their print modes, so there is no API key and no SDK — do not add one.
The interactive spellings for a hand-off are copied from Omarchy's
`omarchy-agent`, but the window is a plain `xdg-terminal-exec` rather than
`omarchy-launch-tui --app-id=org.omarchy.agent`: window rules for opacity and
blur are keyed on the terminal's own class, so a dedicated app-id gives the
hand-off a look the user never chose.

Three runtime traps, all found the hard way: **stdin must be closed**
(`stdin=DEVNULL`) or `codex exec` waits on it forever and the panel just
hangs; **presence is Omarchy's test, not `PATH`** (`~/.local/bin` user
install, else `mise where`, else the agent's own installer `--check`) because
Omarchy leaves a mise shim on `PATH` for every agent it knows, installed or
not; and **a failure is diagnosed from short, non-log lines only** — Codex
logs a 47KB model catalogue to stderr, and matching "sign in" anywhere in it
reported a signed-in CLI as signed out. Being out of allowance
(`error: "quota"`) is kept apart from being signed out (`error: "auth"`),
since only the latter has a sign-in worth opening. The conversation lives in `AiSession.qml`
and travels in the prompt (last 8 turns) because print mode remembers nothing.
The payload goes in as `--json '<object>'`, not stdin. Launchers: `terminal`
(`omarchy-launch-tui`), `tmux` (new window in the *Work* session), `herdr`
(`herdr tab create` → `herdr pane run`).

Signing in is handed to the CLI, through that same launcher: the agent opens
its own browser, waits for the callback and writes its own credentials, so
there is nothing for the panel to drive. `--login` chains the pending question
after the sign-in (`login; exec <agent> "<question>"` — `;` and not `&&`, so a
failed sign-in still leaves the agent on screen saying why), and the user comes
back to a terminal that is already asking what they asked here.

### Search.qml and the stores

`Search.qml` is wiring: it decides which view shows (`view`: `search` |
`settings` | `setup`) and which of the field and the list has the keyboard
(`focusArea`, a two-state machine — Enter searches and stays in the field;
`j`/Down step into the results). Everything else
is held by non-visual `Item`s in `src/components`, the way first-party
plugins keep state in a `Service.qml`:

- `ConfigStore.qml` — the config file: `FileView` watch, `reload()`,
  `change(key, value)` written straight through.
- `Engine.qml` — the SearXNG instance: `state` (`unknown`/`running`/`stopped`),
  `probe()` via `bin/search --status`, `start()`/`stop()` via `bin/searxng-up`
  in a terminal. Paths come from `Qt.resolvedUrl` so the dev symlink works.
- `SearchSession.qml` — the query, the page cache (`pages`/`pageIndex` — `h`
  never refetches), the `ListModel` the list paints, and the `Process` that
  runs the backend. Raises `engineDown`, `pageShown`.
- `AiSession.qml` — the transcript, the agent list from `bin/ask --agents`,
  `ask()`, `launch()`. `AnswerView.qml` reads the transcript with vim keys
  driven by the TextEdit's own layout (`positionAt`/`positionToRectangle`).

Each view owns its own keys (`ResultList`, `AnswerView`, `SettingsPage`,
`SetupPrompt`, `VimTextField`) and raises intent as signals — `escaped`, `settingsRequested`,
`closed` — rather than reaching into the panel. Add a key to the view it
belongs to, and a new piece of state to the store that owns it; `Search.qml`
should only ever gain a signal connection.

The two panes that are *read* with vim keys — the result list and the answer
view — share their keymap rather than each spelling one out: `src/lib/keys.mjs`
holds the tables and turns a chord plus whatever is pending into a command
name, and each pane switches on that name. `j`/`k`/`gg`/`G`/Enter therefore
cannot drift apart between them, and the `g` prefix is written once. Qt's key
enums become chord strings in `src/components/chord.js`, which is a plain
(non-`.pragma library`) JS import precisely so it can see `Qt` — the `.mjs`
next door cannot, because node loads it too. `VimTextField` keeps its own
dispatch: counts, operators and pending finds make it a different machine, and
flattening it into a table would hide that rather than simplify it.

Settings live in `~/.config/omaseek/config.json`, shared by the panel and
`bin/search` — **the option lists are declared once in `src/lib/settings.mjs`**
and mirrored in `bin/search` (`PAGE_SIZE_CHOICES`); change both. `searxng_url`
is read by `bin/search` and never written by the panel, so `writeSettings` must
keep preserving keys it does not own.
Writes go through `writeSettings`, which preserves keys it does not own so the
file stays hand-editable. A `FileView` watches it and `open()` re-reads it, so
an external edit applies on the next summon. Every reader treats an unreadable
config as defaults: a typo should cost one setting, not the search bar.

Theming is inherited, never hardcoded — paint with the `[menu]` tokens from
`qs.Commons` (`Color.menu.*`, `Style.*`, `Border.surfaceSpec`) as the
first-party Omarchy overlays do, and theme switches follow for free. The
layer-shell and open/close/dismiss/toggle contract mirrors
`shell/plugins/emojis/Emojis.qml` in the Omarchy tree so shell IPC works.

## Conventions

- The repo lives outside `~/.config/omarchy/plugins/` and is symlinked in. Never
  suggest `omarchy plugin remove` — it deletes through the symlink. Use
  `rm ~/.config/omarchy/plugins/omaseek`.
- Commit subjects are lowercase-ish prose in the imperative describing the
  behaviour change, not the files ("Page results with h and l instead of
  scrolling"). Bodies explain *why*, and record runtime traps found along the way.
- Comments explain the non-obvious constraint (why a cookie jar, why the whole
  nav form, why a separate process), not what the line does.
- The vim layer deliberately stops short of `.` repeat, macros, marks, named
  registers and linewise visual — a single-line field gets little from them.
- **`KEYS.md` is the keybinding reference**, flat and greppable for exactly this
  reason. It is the answer to "what does this key do" and to "is that key
  free" — read it before adding a binding, and update it in the same commit
  that changes one.
