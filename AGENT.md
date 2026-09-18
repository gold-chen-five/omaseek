# AGENT.md

This file provides guidance to coding agents when working with code in this repository.

## What this is

`omaseek` — a web search overlay with vim keybindings, packaged as an
**Omarchy 4 plugin**. It is not a standalone app: `manifest.json` declares an
`overlay` entry point (`src/Search.qml`) that is loaded *in-process* by the
running `omarchy-shell` Quickshell instance. There is no build step, no package
manager, and no dependencies — Python is stdlib-only and the JS is plain ES
modules run by node's own test runner.

## Commands

```bash
./bin/test                              # offscreen QML, Python and node tests; no compositor/network
node --test test/motions.test.mjs       # one file
node --test --test-name-pattern 'iw'    # one test by name

./bin/search "python asyncio" | jq      # exercise the backend on its own
./bin/search --next "$(./bin/search rust | jq -c .next)" | jq   # page 2
./bin/ask --agents | jq                 # which agent CLIs are installed, and the default
./bin/ask --json '{"question":"…"}'     # one chat turn through the configured agent

omarchy-restart-shell                   # after every QML change — see below
omarchy-shell shell rescanPlugins       # re-reads the plugin list; will not reload live QML
./bin/dev-watch                         # only for a checkout outside the plugins dir
quickshell log -p /usr/share/omarchy/shell -f   # QML errors and console.log (not journald)
```

Run `./bin/test` after touching anything in `src/lib`. There is no linter.
The QML test drives `VimTextField` with real key events; its import stubs expose
only the shell types needed to instantiate the field outside Quickshell.

**A QML change needs `omarchy-restart-shell`, not a rescan.** Omarchy watches
the plugins directory and rescans on save, but `keepLoaded: true` means this
panel is already instantiated, and a rescan re-reads the plugin list rather
than rebuilding a live component — measured: an edited button label did not
appear after `rescanPlugins`, and did after a restart. Then check
`quickshell log`: a QML error does not announce itself, the panel simply stops
existing, which is what makes `SUPER + D` look broken.

## Architecture

### The pure/impure split

One rule governs the layout: **anything that is a pure function of its inputs
lives in `src/lib` as an `.mjs` ES module; everything that needs Qt stays in
QML.** The same file loads in both (`import "../lib/motions.mjs" as Motions` in
QML, `import` in node), so cursor arithmetic, escape-sequence matching, page
merging and config parsing are all under test without a compositor.

- `src/lib/json.mjs` — reading one of our own hand-editable JSON files: nothing here throws, so an unreadable file is an empty one
- `src/lib/motions.mjs` — cursor motions (`w b e f t 0 ^ $`), `(text, pos) -> pos`
- `src/lib/textobjects.mjs` — `iw aw i" a(` … `(text, pos) -> {start, end}`
- `src/lib/keymap.mjs` — the insert-mode escape sequence (`jk`) and its config
- `src/lib/search.mjs` — result normalising, de-duplication, status/error strings
- `src/lib/settings.mjs` — config text → settings, and the settings-page row list
- `src/lib/markdown.mjs` — the agent's Markdown → the rich-text subset a TextEdit colours; the transcript layout
- `src/lib/keybinds.mjs` — `ACTIONS`, every rebindable key; binding text ↔ chords (`gA` ↔ `g A`); `panelChords()` for the field's and the answer's table
- `src/lib/keys.mjs` — chord → command name for the reading panes, the `gg`/`gv` prefix machine, and the clash check for a rebound key
- `src/lib/states.mjs` — the panel's `VIEW`, `PANEL` and `FOCUS` values; never write them as bare strings
- `src/lib/urls.mjs` — the bare URL under the cursor for `gx`, and which links may open (http/https only)
- `src/lib/sessions.mjs` — the ring of ten saved conversations: recording, walking, forgetting, and its file
- `src/lib/popup.mjs` — where a settings dropdown's list opens so it stays on screen: below, above, or shrunk to scroll
- `src/lib/pager.mjs` — which page squares the results strip shows: every page while they fit, then a window around the one being read

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
`{ok: false, error, message}` — and exits 0 even on a handled failure. Each row
carries `engines` (`"brave, bing"`), which `ResultRow` shows after the domain; a
string, because a ListModel turns an array role into a nested model. Errors
are typed (`network`/`http`/`usage`), and a failure carries `setup: true` for
the one case a person can fix from the panel: the instance is not running.
`Search.qml` turns that into the SetupPrompt view, which explains Docker and
asks, rather than showing an error the user cannot act on. A 403 is *not*
marked `setup` — SearXNG ships `formats: [html]`, so the JSON API is off until
`settings.yml` enables it, and the error message names that fix.

**A failed page is not the end.** `grow_session` used to clear `next` when a
fetch failed, so a timeout on page 3 read as `· end` and could never be retried.
It now keeps the continuation, saves the buffer, and `emit_page` fails the whole
page with `retry: true` — a short page would be cached by the panel as final.
`SearchSession` keeps the page's `next`, sets `pageError`, and the status line
says `page failed · l retries`; the same `--next` payload resumes. The first page
is the exception: rows to read beat an error.

Two rows report on them, because one number cannot. **Search speed**
(`--time`) sends the query a search sends — every engine at once — and reports
that wait: SearXNG queries engines together, so a keypress waits for the
slowest, never the sum. **Test engines** (`--test`) asks each engine alone and
in turn, for the rows and the time that a combined query cannot tell apart, and
puts a refused engine's reason in brackets after its count and time
(`google 0 in 3 ms (CAPTCHA)`): a CAPTCHA answers in 3 ms with no rows, which
without the brackets reads as the fastest engine of the lot. SearXNG's own
`Suspended: ` prefix is dropped there, since the brackets already say it.

`bin/search --test` is the Settings → Test engines row: one real query with the
configured engines and language, reported as its time, rows per engine and
SearXNG's `unresponsive_engines` (Google answers `Suspended: CAPTCHA` locally).
`Engine.test` holds the answer; it runs in-process rather than in a terminal,
and changing an engine or the language clears it, since it described the old
ones.

`bin/search --version` is the Update row's hint: `/config`'s `version`
(`2026.9.16+461f174b0`) against the dated Docker Hub tag sharing `latest`'s
digest (`2026.9.16-461f174b0`) — `latest` names no version itself. Current means
the same commit, or a newer date (a local build). Docker Hub is sent the tags URL
and nothing else, and an unreachable Hub still reports the running version.
`Engine.probe()` runs it each time Settings opens.

Updates are deliberate rather than tied to opening the panel. Settings launches
`bin/searxng-up --update` in a terminal: it pulls before touching the current
container, does not restart an already-current image, preserves a stopped state,
and restores the previous image when a replacement fails its JSON readiness
probe. The config mount under `~/.config/searxng/` is never replaced.

**Removal asks about SearXNG** although Omarchy runs nothing from a plugin it
removes (no hook, no manifest field — its README says so). What it does do is
disable the plugin first, which destroys the panel, and delete or move the
folder a moment later. So `Engine` stages `bin/on-remove` and `bin/searxng-up`
into `$XDG_RUNTIME_DIR/omaseek-removal/` on load, and runs that copy on
`Component.onDestruction`: if the manifest is gone within five seconds, it
opens a terminal and asks; a disable, a restart or a hot reload leaves the
manifest and asks nothing. Measured with a throwaway plugin on 2026-09-17: the
panel is destroyed with the manifest present, and it is gone a second later.
`bin/uninstall` asks in its own terminal and touches `searxng-decided` there,
so the question is not put twice. A plugin already disabled when it is removed
is never unloaded, so that removal cannot ask.

**Speed**: one request per page is the budget. `emit_page` fills the buffer to
exactly the page — an earlier lookahead row cost a whole extra request whenever
a SearXNG page came back exactly `PAGE_SIZE` long, doubling latency on a
keypress. Everything else is SearXNG waiting on upstream engines — and it
waits for every engine in the category, so `searxng_engines` in config.json
(Settings → one switch per engine, passed through as `engines=`) is the big lever: naming the ones
that answer took a query from ~1.1 s to ~0.3 s locally. `outgoing.request_timeout`
in its `settings.yml` is the backstop.

`DEFAULT_ENGINES` in `bin/search` is what an install ships, because the
installer never writes a config and an unnamed list means *every* enabled
engine — the slow path. Measured locally: **brave** (20 rows, pages),
**bing** (10 rows, fastest, but `paging: false`, so brave carries `h`/`l`) and
**google** (10 rows, pages, but CAPTCHAs under load) and **google cse** —
Google through its embeddable search box (`cse.google.com/cse/element/v1` with a
borrowed `cx`, no key), which answered 20 rows in ~0.5 s on 2026-09-17 while
plain google was suspended. The shipped default is **google cse, bing,
brave**; plain google is offered as a switch but off, since it CAPTCHAs. google
cse was dropped once before (2026-09-14) for quota-suspending fastest of all,
which is why brave stays in the defaults to carry paging if it goes quiet. Most of the rest answer with a CAPTCHA, a parsing
error, or nothing at all, and `wikipedia`/`wikidata` return *no rows by
construction* — they answer in `infoboxes`, which `parse()` does not read.
SearXNG ignores an engine name its instance lacks, so the list is safe to ship;
an explicit `[]` is the escape hatch that hands the choice back to SearXNG.
The settings page switches google cse, bing, brave, google, duckduckgo,
startpage, yep, yandex and yahoo (`ENGINE_CHOICES`, with `ENGINE_LABELS` for the
two whose SearXNG name capitalises wrong; `DEFAULT_ENGINES` is the first four),
and shows any other name found in the list as a switch too, so a hand-typed
engine survives a toggle. The four added on 2026-09-18 are what answered when
28 of SearXNG's 58 general engines were each asked three queries here:
**startpage** the most rows (33-37) but 1-2 s, **yep** a steady 20, **yandex**
10, **yahoo** 7. mojeek and qwant refused every query, mwmbl suspended itself
after one, and google and duckduckgo answered or CAPTCHAd depending on the hour
— which is why neither is a default, and why the Test row sits at the top of
the section. `searxng_language` is sent as `language=`; `default` is
written as an absent key. Both are part of the buffer's cache key, or switching
language would serve page 2 from the old language's buffer.

Pages are sliced from a session buffer under `~/.cache/omaseek/` rather
than served straight from SearXNG, because a SearXNG page is however many
engines answered in time. Rows are de-duplicated on URL *and* domain+title, in
`absorb()` and again in `search.mjs`.

### bin/ask — the AI half

Same shape as `bin/search`: a separate stdlib-Python process, one JSON object
out, exit 0 on handled failure. It speaks to **agent CLIs already installed**
(`claude`, `codex`, `crush`, `opencode`, `gemini`, `hermes`, `copilot`, `cursor-agent`)
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
reported a signed-in CLI as signed out. Crush has
three quirks of its own, all in its `AGENTS` entry: only `crush run` takes
`--model` (`launch_model: False` keeps it off the interactive `crush --yolo`);
`crush models` lists every model of every provider it knows, ~1,600, so the list
is cut to the providers named in its `crush.json` files (`crush_providers`,
keys only — the values are tokens); and its errors are boxed and wrapped, so
`wrapped_errors` joins them back into one sentence before they are classified.
Being out of allowance
(`error: "quota"`) is kept apart from being signed out (`error: "auth"`),
since only the latter has a sign-in worth opening. The conversation lives in `AiSession.qml`
and travels in the prompt (last 8 turns) because print mode remembers nothing.
The payload goes in as `--json '<object>'`, not stdin. Launchers: `terminal`
(`omarchy-launch-tui`), `tmux` (new window in the *Work* session), `herdr`
(`herdr tab create` → `herdr pane run`).

**The last ten conversations are kept**, newest first, and `ctrl+n` walks them
while `ctrl+x` forgets one; `ctrl+c` leaves the current one in the ring rather
than losing it. `sessions.mjs` holds the rules and `SessionStore.qml` the file,
which — unlike `ConfigStore` — is read **once and never watched**: the panel's
place in the ring is an index into that list, so a re-read behind its back would
move the conversation under the cursor. The read is asynchronous, so
`remember()` waits for `store.ready`; recording before the file lands would
write a lone conversation into a ring about to be replaced by the saved ten. A
conversation being answered into keeps its place rather than jumping to the
front, so walking the ring stays predictable. The strip is the same three
actions with a mouse: a square is `openSession(index)`, `+` is `newChat()`.
`ctrl+shift+x` forgets the lot; since nothing here can be undone and the panel
has no dialog, it arms on the first press and the status line says what the
second one will do (`clearArmed` in `Search.qml`, `confirmClearText` in
`search.mjs`), with every other session key calling it off. Shift became a
modifier for that binding: `chord.js` spells a ctrl chord with shift `C-S-x`,
and `keybinds.mjs` parses `ctrl+shift+x` — shift alone is refused, because on
its own it is how a capital is typed and `X` already spells that.

**A turn outlives the conversation being on screen.** `ctrl+c` while the agent
is thinking starts a new conversation and leaves the old turn running, so
`AiSession` keeps **one `Process` per question** (`turnComponent`, created with
`createObject`) tagged with `sessionId`, and `deliver()` routes the answer home:
to `history` when that conversation is still in front of the reader, otherwise
straight into its ring entry by id (`indexOfSession`), which is why a
conversation's `id` is assigned once — by `remember()`, passed into `record()` —
and never reassigned. A single shared process would have been killed by the next
question. `pendingIds` is what the strip's dot and `show()`'s `thinking` status
read.

Two traps around this: stopping a `Process` still ends its stream, and the
collector reports the nothing it read as an unreadable answer — that is the
`⚠ Could not read the agent's output` that ctrl+c used to leave in the *new*
conversation — so `cancelTurn()` disowns the turn (`forget()`) before stopping
it and `deliver()` ignores a stream nobody waits for. And the sign-in hand-off
takes the screen, so a background failure only records its error; only the
conversation in front of the reader opens a terminal. `dropUnanswered()` still
takes out a conversation left with a question that has no answer *and* nothing
running, so an abandoned empty question does not keep a square — unless it ends
in a stop, which was a decision to come back and retry.

**Stop and retry**. Stop is fixed, not an `ACTIONS` entry: `q` in the answer's
table, and in the field's normal mode `q`, or `esc` while `stoppable` — where it
would otherwise close the panel. A letter could never be a field/panel binding.
Asking moves the reader into the answer, as Enter in search moves them to the
results, so `q` is at hand there; from the field it is `esc`, twice if still in
insert. Retry is
`ctrl+shift+r`, shift because `ctrl+r` is the field's redo. `AiSession.stop()` cancels the live turn and appends
`Sessions.stoppedTurn(partial)`: the words streamed so far as an assistant turn
marked `stopped: true`, or an error turn when nothing had arrived. `stopped`
is the one extra field `asTurns` keeps. A stopped reply is shown with `■ stopped`
under it and never travels in a prompt (`promptTurns`). `retry()` cuts
everything after `Sessions.retryPoint(history)` — the last question, when only
failures, stops or nothing follow it (a turn a shell restart lost) — and asks it
again. Stopping kills `bin/ask`, so the agent CLI it started is spawned with
`PR_SET_PDEATHSIG` (`die_with_parent`): the kernel ends it however `bin/ask`
dies, SIGKILL included, and a stopped answer does not keep an agent running and
billing in the background.

Handoffs open an editable draft, never an initial submitted prompt. `bin/agent-draft`
runs the interactive CLI in a PTY, waits for bracketed-paste mode and a second, then sends only a
bracketed paste (no Enter) — and **keeps sending it until the draft shows on screen**. Enabling
bracketed paste is not being ready for one: OpenCode 1.18 enables it at ~0.9 s but draws its
input box at ~3.5 s, dropping every earlier paste without a trace, which made `ga`/`gA` open
an empty agent. No quiet period marks readiness (its logo is followed by 2.5 s of silence), so
the paste is confirmed by its echo — the draft's first characters, or the `[Pasted …]` label
agents show for a long one — retried every 1.5 s for up to 20 s. Retries stop the moment the
reader types; the terminal's own answers to capability queries arrive on the same input and
are escape sequences, so they do not count as typing (counting them cancelled every retry). Terminal control characters
are removed from the draft. The same wrapper works in terminal, tmux and herdr;
a private temporary prompt file is deleted when the wrapper reads it. Do not
restore prompt arguments that auto-submit. Both reading panes hand off with the
same keys: `ga` the selected result's bare URL — the draft is editable, so a
title and snippet in front of it only get in the way of the question being typed
around it — or the selection / the reply under the cursor with its question;
`gA` every URL on the page one per line, or the whole conversation, built from
the turns (`transcript.mjs`), never the rendered text with its placeholder dots.
Every panel key is one entry in `ACTIONS` (`src/lib/keybinds.mjs`): its
default, where it is read, and its Settings → Keys row. `bindingProblem` in
`keys.mjs` refuses a key another action or a fixed vim key already holds —
including a prefix, since `g` alone would swallow `gg`. Link lookup reads
getFormattedText for the cursor character rather than coordinate-based linkAt,
which can hit a neighboring paragraph. Bare domains also work with gx.

Signing in is handed to the CLI through the same launcher. After login, a pending
question also opens as a draft; the user submits it themselves.

### Search.qml and the stores

`Search.qml` is wiring: it decides which view shows (`view`: `search` |
`settings` | `setup`) and which of the field and the list has the keyboard
(`focusArea`, a two-state machine — Enter searches and focuses the first
result when it arrives; `j`/Down also step into existing results). Everything else
is held by non-visual `Item`s in `src/components`, the way first-party
plugins keep state in a `Service.qml`:

The field's Vim mode survives closing and reopening the panel, and switching
between search and AI with Tab; only an explicit mode-changing action changes it.

- `JsonFile.qml` — one of our JSON files under an XDG base: read whole, written
  whole, and the place the mkdir trap is settled — `setText` fails silently when
  the directory is missing, the state a machine is in before its first write, so
  every write waits for one. The three stores below differ only in where the
  file lives, whether it is watched, and what the text means.
- `JsonProcess.qml` — a `bin/` helper run for one answer. They all print one JSON
  object and exit 0, so `parsed(payload)` and `unreadable(raw)` is the whole
  protocol; `start(command)` stops first, because a running `Process` keeps its
  old command until it does.
- `ConfigStore.qml` — the config file: watched, `reload()`,
  `change(key, value)` written straight through.
- `Engine.qml` — the SearXNG instance: `state` (`unknown`/`running`/`stopped`),
  `probe()` via `bin/search --status`, and start/stop/update via `bin/searxng-up`
  in a terminal. Paths come from `Qt.resolvedUrl` so the dev symlink works.
- `SearchSession.qml` — the query, the page cache (`pages`/`pageIndex` — `h`
  never refetches), the `ListModel` the list paints, and the `JsonProcess` that
  runs the backend. Raises `engineDown`, `pageShown`. `5gp` jumps: a page's
  continuation only arrives with the page before it, so `goToPage` sets
  `pageTarget` and each answer asks for the next until it lands, `h` or a
  failure calls it off, and `pageJumpTarget` caps one jump at ten new requests
  so a stray `500gp` cannot spend five hundred.
- `AiSession.qml` — the transcript, the agent list from `bin/ask --agents`,
  `ask()`, `launch()`, and the ring of saved conversations (`nextSession()`,
  `closeSession()`, `sessionIndex`). `AnswerView.qml` reads the transcript with
  vim keys driven by the TextEdit's own layout (`positionAt`/`positionToRectangle`).
- `SessionStore.qml` — the last ten conversations in
  `~/.local/share/omaseek/sessions.json`, written whole on every turn.
- `HistoryStore.qml` — the last twenty-five queries, the same shape and read
  once for the same reason.
- `SettingsDropdown.qml` — Omarchy's qs.Ui `Dropdown`, copied because its list
  always opened below at eight rows with no window bound and ran off the screen
  for a row low on the page; this one places the list with `popup.mjs`. Keep
  its look in step with the original under `/usr/share/omarchy/shell/Ui`.
- `PageTabs.qml` — the same squares for the pages of results, numbered by its
  own `page_numbers` setting rather than the lines', one per page held
  plus a `›` for the one not fetched yet; `picked(page)` is `goToPage`, so the
  mouse and `5gp` end in the same place. Only one strip shows at a time —
  pages in search, conversations in AI — and `content.viewHeight` subtracts
  whichever it is.
- `SessionTabs.qml` — the numbered squares under the status line, one per saved
  conversation plus a `+`, with a pulsing dot on any whose answer is still
  coming; it raises `picked(index)` and `started()` and knows nothing else. It takes its room from the view below through
  `content.viewHeight`, which is why the two panes and the settings page share
  one height rather than each subtracting the rows above.

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
next door cannot, because node loads it too. `measure.js` is a plain import for
the same reason: both panes light a character, and `positionToRectangle` gives a
caret rather than a box, so the width is worth deriving once. What they draw
over it is `MatchHighlight.qml`, shared by the field's `f`/`t` hits and the
answer's `/` and `f`/`t` ones. `VimTextField` keeps its own key dispatch:
counts, operators and pending finds make it a different machine, and flattening
it into a table would hide that rather than simplify it.

The answer view needs that machine too (`3w`, `yiw`, `viw`, `fx`), so it runs
its keys through `src/lib/grammar.mjs` first: counts, the `y` operator, the key
after `f`/`t` and after `i`/`a`, then the table for everything else. Every
motion there answers *where it lands* (`motionTarget`) rather than moving, so
one target moves the cursor, stretches a selection, or bounds a yank. Finds and
text objects are confined to the logical line (`findInLine`, `resolveInLine`),
as vim's are; the transcript is one long text. `yy` copies the current displayed line (with counts for multiple lines),
and `p` puts into the ask bar, which reads the clipboard
through the TextArea's own `paste()` — no `wl-paste` round trip.

The keys that belong to the *panel* rather than to a pane — search, the session
keys, settings, the mode switch — travel as one object: `Keybinds.panelChords(settings)`
maps action id → parsed chord, and the field and the answer both take it as
`chords`. A new panel key is an entry in `ACTIONS` and a case in
`VimTextField.panelCommand`, not a property threaded through `Search.qml`.

Settings live in `~/.config/omaseek/config.json`, shared by the panel and
`bin/search` — **the option lists are declared once in `src/lib/settings.mjs`**
and mirrored in `bin/search` (`PAGE_SIZE_CHOICES`, `DEFAULT_ENGINES`,
`LANGUAGE_PATTERN`); change both. `searxng_url`
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

- **This repo *is* the installed plugin**: it lives at
  `~/.config/omarchy/plugins/omaseek`, which is what
  [the plugin docs](https://plugins.omarchy.org/develop.html) describe — work
  in a user-owned copy under that directory, and `omarchy-plugin-validate`
  skips `.git` precisely because installed plugins are git checkouts. Edits are
  therefore live; there is nothing to copy or link.
  - **Users install with `omarchy plugin add <url> --enable`**, which clones
    into that directory with a real `.git`; `omarchy plugin update` and
    `remove` both depend on it (update skips a plugin without a `.git`
    directory). `omarchy plugin validate` must pass on a clean clone: it
    refuses any symlink in the folder, which is why `CLAUDE.md` is a one-line
    `@AGENT.md` import rather than a link.
  - **This dev checkout's `.git` is a pointer** to `~/.local/share/omaseek.git`
    (`git init --separate-git-dir`), from when Omarchy's watcher excluded
    nothing and every `git status` reloaded the panel ("k stops working after a
    while"). The watcher now skips `.git` paths (`PluginRegistry.qml`,
    `localPluginIdForPath`), so a fresh clone needs no such move, and
    `bin/install` no longer makes it. Never run `omarchy plugin remove` or
    `bin/uninstall` here: this checkout is the source.
- Commit subjects are lowercase-ish prose in the imperative describing the
  behaviour change, not the files ("Page results with h and l instead of
  scrolling"). Bodies explain *why*, and record runtime traps found along the way.
- Comments explain the non-obvious constraint (why a cookie jar, why the whole
  nav form, why a separate process), not what the line does.
- The vim layer deliberately stops short of `.` repeat, macros, marks, named
  registers. Shift+V selects lines in the ask bar and response.
- **`KEYS.md` is the keybinding reference**, flat and greppable for exactly this
  reason. It is the answer to "what does this key do" and to "is that key
  free" — read it before adding a binding, and update it in the same commit
  that changes one.
