# omaseek — Omarchy web search panel

A keybind-summoned web search overlay for Omarchy 4, with vim keybindings.
Searches go through a SearXNG instance you run yourself.
Runs as a plugin inside the existing `omarchy-shell` Quickshell process, so it
opens instantly and follows the active Omarchy theme with no configuration.

## Usage

Press **SUPER + D**.

### Search bar

| Key | Action |
|---|---|
| *(type)* | build the query |
| `Enter` | run the search — focus stays in the field |
| `↓` | step down into the results, from either mode |
| `Esc` | leave INSERT for NORMAL mode |
| `jk` | the same, without reaching for Esc |
| `j` (in NORMAL) | step down into the results |
| `Esc` (in NORMAL) | close the panel |
| `Ctrl+W` / `Ctrl+U` | delete word back / to start (insert mode) |
| `Tab` | switch the field between searching and asking (see *Ask*) |
| `Ctrl+S` | settings |

From NORMAL mode the result list is simply the line below, so `j` moves into
it — the panel reads as one vertical buffer rather than two separate widgets.

`jk` is vim's `inoremap jk <Esc>` in miniature: the `j` types as normal and is
taken back when the `k` lands within 200 ms. Type the two keys further apart
than that and they stay text, which is how a query that genuinely contains
`jk` still works. Both the sequence and the window are yours to set in
`~/.config/omaseek/config.json`:

```json
{
  "escape_sequence": "jk",
  "escape_timeout_ms": 200
}
```

| Value | Effect |
|---|---|
| `"kj"` | any run of two or more keys works |
| `["jk", "kj"]` | several sequences at once |
| `""` | turn it off — `Esc` only |

`escape_timeout_ms` is how long the whole run may take, clamped to 20–5000 ms.

The panel re-reads the file every time it opens, so an edit applies on the next
**SUPER + D**. Anything unreadable in it — no file, malformed JSON, a key of the
wrong type — leaves the defaults standing rather than breaking the search bar.

NORMAL mode supports a practical vim subset:

- **Motions** — `h` `l` `w` `W` `b` `B` `e` `E` `0` `^` `$`, `f{char}` `F{char}`
  `t{char}` `T{char}`, and `;` `,` to repeat a find
- **Text objects** — `iw` `aw` `iW` `aW`, quotes `i"` `a"` `i'` `a'` ``i` `` ``a` ``,
  and brackets `i(` `a(` `i[` `a[` `i{` `a{` `i<` `a<` (with `b` and `B` as aliases) —
  so `diw`, `ci"`, `da(` and `viw` all work. Brackets pick the innermost
  enclosing pair; a pair that never closes cancels the operator
- **Operators** — `d` `c` `y` with any motion, `dd` `cc` `yy`, `D` `C` `Y`
- **Edits** — `x` `X` `s` `S` `p` `P`
- **Modes** — `i` `a` `I` `A` to insert, `v` for charwise visual
- **Undo** — `u`, `Ctrl+R`
- **Counts** — `3w`, `d2w`, `2x` …

Yanks and deletes fill the unnamed register *and* the system clipboard
(`wl-copy`), so `y` in the panel pastes anywhere else.

The cursor shows the mode: a block in NORMAL/VISUAL, a thin bar in INSERT.

### Results

| Key | Action |
|---|---|
| `j` / `k`, `↓` / `↑` | move the cursor within the page |
| `l` / `h`, `→` / `←` | next / previous page |
| `gg` / `G` | first / last result on the page |
| `Ctrl+D` / `Ctrl+U` | half-page down / up |
| `Enter` | open the highlighted result in the browser |
| `i` or `/` | back to the search bar (INSERT) |
| `Esc` | back to the search bar (NORMAL) |

Each result shows the site's favicon, falling back to the domain's initial.

Results are **paged, not scrolled**: `j` and `k` stay inside the current page,
and `l` and `h` step between pages. Every page holds the same number of
results, and the status line names the page you are on and marks `· end` on
the last one. Pages you have already visited are cached, so `h` never
refetches — only `l` past the furthest page hits the network.

Results open with `omarchy-launch-browser`, which respects your default browser.

### Ask

`Tab` turns the search bar into a question bar — the text stays, so a query
that found nothing is one keystroke from being a question. Enter sends it to
an AI coding agent already on the machine, in its print mode (`claude -p`,
`codex exec`, `hermes chat -q`…), and the answer renders below as Markdown.
The panel keeps the conversation, so a follow-up question sees the earlier
turns. Nothing new to sign in to: whatever the CLI is signed into answers —
and if it is signed out, the panel opens that CLI's own sign-in in a terminal
(`claude auth login`, `codex login`, …) instead of showing the error; ask
again once it is done. Being *out of allowance* is a different thing and says
so where the answer would be, since signing in again would fix nothing. Questions sit in a quiet grey block after `>` and
replies follow a `⏺`, the way Claude Code lays out its own transcript.

`j` or `↓` steps into the answer, which reads with the same keys as the field:

| Key | Action |
|---|---|
| `j` `k` `h` `l` `w` `b` `e` `0` `$` `gg` `G` | move the cursor |
| `Ctrl+D` / `Ctrl+U` | half a screen |
| `v` / `V` | select by character / by line; `Esc` drops it, `gv` brings it back |
| `y` | yank the selection (or the whole answer) to the clipboard — it stays lit for a beat, as LazyVim's yank highlight does |
| `Enter` | hand the selection — or the whole answer — to the agent in a terminal |
| `i` / `/` | back to the field, typing the next question |
| `Esc` | back to the field, NORMAL mode |
| `Tab` | back to searching |

The hand-off is the point: read, select the bit that matters, `Enter`, and
the agent opens with it as its prompt — in a fresh terminal the way Omarchy's
own `Super+A` does, or in a new tmux window or herdr tab, whichever *Hand off
to* is set to. Which agent answers and receives is *Ask* in settings; the
default follows `omarchy default agent`.

## How it works

```
manifest.json          plugin manifest — overlay kind, keepLoaded for instant summon
src/
  Search.qml           entry point: layer-shell window, which view shows, who has focus
  components/
    ConfigStore.qml    config.json, watched and written through
    Engine.qml         the SearXNG instance: probe it, start it, stop it
    SearchSession.qml  one query, its page cache, the backend process
    AiSession.qml      the conversation with an agent, one process per turn
    VimTextField.qml   the vim mode machine and key dispatch
    ResultList.qml     the list, its cursor, and its keys
    ResultRow.qml      one result: favicon, title, domain, snippet
    AnswerView.qml     the agent's answer, read and selected with vim keys
    SettingsPage.qml   the settings rows and their keys
    SetupPrompt.qml    shown when the instance is not running
    StatusLine.qml     mode on the left, search state on the right
  lib/
    motions.mjs        pure cursor motions
    textobjects.mjs    iw, a", i( and the rest
    keymap.mjs         the insert-mode escape sequence and its config
    search.mjs         result merging, error and status strings
    settings.mjs       config text -> settings, and the settings-page rows
    markdown.mjs       Markdown -> rich text, so a question and a reply can differ in colour
bin/
  search               SearXNG client — stdlib Python, one request per page
  ask                  agent client — lists them, runs a chat turn, opens a hand-off
  searxng-up           create or start the SearXNG container, idempotent
  dev-watch            hot reload during development
  test                 runs the unit tests
test/                  node tests for src/lib
```

The split follows one rule: anything that is a pure function of its inputs
lives in `src/lib` as an ES module, and everything that needs Qt stays in QML.
`.mjs` modules load in both QML (`import "lib/motions.mjs" as Motions`) and
node, so the cursor arithmetic and the paging rules are tested directly:

```bash
./bin/test          # 72 tests, no shell and no network
```

That is why `VimTextField.qml` holds only the mode machine and key dispatch —
every `w`, `b`, `e`, `f` and count calculation is in `motions.mjs` under test,
the escape-sequence matching is in `keymap.mjs`, and result de-duplication and
status strings are in `search.mjs`.

Theming is inherited: the panel paints with the `[menu]` surface tokens from
`qs.Commons` (`Color.menu.*`, `Style.*`), the same ones Omarchy's own overlays
use, so every theme and light/dark switch applies automatically.

`bin/search` is deliberately a separate process rather than QML JavaScript.
HTML parsing is the fragile part, and this keeps it testable on its own:

```bash
./bin/search "python asyncio" | jq
```

It distinguishes a network failure, a misconfigured JSON API, and a genuinely
empty result set, so the panel never reports "no results" when the instance was
never reached. The one failure a person can fix from the panel — the instance
not running — is marked `setup: true`, and that is what raises the prompt.

Paging is a plain `pageno`, handed back as `--next '<json>'`:

```bash
./bin/search --next "$(./bin/search rust | jq -c .next)" | jq '.results[0]'
```

### SearXNG

The default backend is a **SearXNG instance you run yourself**. It is a
metasearch engine: it queries the upstream engines on your behalf and hands
back merged results, so the panel talks only to your own service. That settles
the terms-of-service question the scraping backend raises, and it paginates
properly — `pageno=2` rather than echoing a hidden form back.

Run it with one command — no arguments, no prior setup:

```bash
./bin/searxng-up
```

It starts the docker daemon if it is stopped, writes `~/.config/searxng/
settings.yml` if it is missing, creates the container (or starts the one you
already have), and waits until the JSON API actually answers before saying
`ready`. Run it again any time: after a reboot, or just to check. It asks for
sudo only where docker genuinely needs it, and says so first.
`./bin/searxng-up --stop` stops the container and keeps it, so the next start is
instant; `--down` removes it as well, keeping only the config.

**Or let the panel ask.** When the instance is not running, the panel does not
leave an error on screen you cannot act on — it explains what SearXNG is, that
it runs in Docker, and that saying yes means a download and a password prompt,
then waits for an answer:

| Key | Action |
|---|---|
| `h` `l` / `←` `→` / `Tab` | move between *Not now* and *Start it* |
| `Enter` | press the highlighted button (*Start it* is where you land) |
| `Esc` | not now — back to the query, still typed |

*Start it* opens a terminal and runs `bin/searxng-up`. The buttons are drawn
the way the shell's own confirm dialog draws its, so saying yes here looks like
saying yes to an update in the Omarchy menu.

A terminal rather than a detached process, because sudo needs somewhere to
prompt and a 200 MB first pull is worth watching.

Point the panel at it in `~/.config/omaseek/config.json`:

```json
{
  "searxng_url": "http://localhost:8888"
}
```

`searxng_url` defaults to `http://localhost:8888` and is hand-edited. It is the
one backend — there is no engine to choose, and so no engine setting.

### Speed

A search costs one request, and its whole cost is SearXNG waiting on the
upstream engines it queries — and it waits for *every* engine in the category,
so the slowest one sets the pace for all of them. Out of the box that includes
engines that only ever fill an infobox this panel never shows (`wikidata` runs
around 0.9 s) and ones that are CAPTCHA'd and return nothing. Naming the
engines that actually answer, in `~/.config/omaseek/config.json`, is the
biggest lever and needs no sudo:

```json
{
  "searxng_engines": ["brave", "google cse", "wikipedia"]
}
```

Measured locally that takes a query from ~1.1 s to ~0.3 s with the same rows.
Use SearXNG's own names (the `/config` endpoint of your instance lists them
with their `enabled` flag); leave the key out to let SearXNG choose. It is
hand-edited, like `searxng_url` — the settings page preserves it.

The second lever is the ceiling SearXNG waits under, in its `settings.yml`:

```yaml
outgoing:
  request_timeout: 2.0        # default is 3.0
  max_request_timeout: 4.0
  enable_http2: true
```

`bin/searxng-up` writes that on a fresh install. The image chowns
`settings.yml` to its own user on first run, so applying it to an instance you
already have takes sudo:

```bash
sudo docker restart searxng   # after editing
```

**The JSON API must be enabled.** SearXNG ships with `formats: [html]`, so the
panel gets an HTTP 403 until `settings.yml` says:

```yaml
search:
  formats:
    - html
    - json
```

The panel names that exact fix when it sees the 403, rather than reporting a
bare HTTP error — and `bin/searxng-up` writes the format in for you on a fresh
install, or warns if an existing `settings.yml` lacks it.

There is no fallback to anything else. An instance that is down raises the
setup prompt rather than quietly searching somewhere you did not choose.

### Uniform pages

A SearXNG page is however many upstream engines answered in time, so paging
straight off it would give ragged pages. Whatever a chunk contains is
accumulated in a session buffer under `~/.cache/omaseek/`, and pages are
sliced from that at a fixed size — every page holds 10, except the last.

That also means fewer requests: a 25-result page covers two and a half of ours,
paging backwards costs nothing, and a page turn tops the buffer up at most
three times so it can never burst. Rows are de-duplicated on URL *and* on
domain+title as they land, because the same document turns up across page
boundaries and under several canonical paths (`/book/` and `/stable/book/`).

The buffer is filled to the page and no further. Asking for one row beyond it
— to know whether a next page exists — used to cost an entire extra request
whenever a SearXNG page came back exactly ten long, doubling the wait on a
keypress. `next` is offered whenever SearXNG still has a page to give; if it
turns out empty, the panel stays put and stops offering more.

The buffer is read only while paging. Pressing Enter always searches afresh.

## Settings

`Ctrl+S` from anywhere in the panel opens the settings page (`Ctrl+,` still
works — it was the original binding). `j`/`k` moves
between rows, `h`/`l` picks a value, `Esc` goes back. Changes are written the
moment you make them — there is no save button to forget.

| Setting | Choices | What it does |
|---|---|---|
| SearXNG | *Start* · *Stop* | Not a setting so much as a switch: the row shows whether the instance answers, and `Enter` opens a terminal that runs `bin/searxng-up` (or `--stop`). Checked each time the page opens. |
| Leave insert with | *typed* | The insert-mode escape sequence — any keys, not a fixed list. `Enter` opens the field, `Enter` again saves, `Esc` discards. Empty turns it off; a single character is refused, since binding one key would make that key untypable. |
| Results per page | 5 · 10 · 15 · 20 | How many rows each page shows, however many SearXNG returns. |
| Ask | default · *installed agents* | Which agent answers and receives a hand-off. *default* is `omarchy default agent`; when that is unset, the first installed one stands in and the row says so. Installed means what Omarchy means by it — a user install in `~/.local/bin`, a mise install, or the Hermes installer's own check — not merely a name on `PATH`, since Omarchy leaves a mise shim there for agents that were never installed. |
| Hand off to | terminal · tmux · herdr | Where `Enter` on an answer opens the agent: a new terminal window (`omarchy-agent`), a new window in the tmux *Work* session, or a new herdr tab. |

The window the two keys must land inside is vim's own `timeoutlen` (1000 ms),
so a sequence that works in your vimrc works here. It is not a setting; set
`escape_timeout_ms` by hand if you really want a different one.

Everything is stored in `~/.config/omaseek/config.json`, which stays
hand-editable — the page writes only the keys it owns and leaves anything else
in the file alone. The file is watched, so an edit outside the panel is picked
up on the next summon.

## Install

```bash
ln -s /mnt/hdd/work/omaseek ~/.config/omarchy/plugins/omaseek
omarchy-shell shell rescanPlugins
omarchy plugin enable omaseek
```

Then add the keybind to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Web search", "omarchy-shell shell toggle omaseek")
```

and `hyprctl reload`.

## Development

The repo lives outside `~/.config/omarchy/plugins/` and is symlinked in.
Omarchy's hot-reload watcher (`inotifywait -r`) does not follow symlinks, so run:

```bash
./bin/dev-watch
```

to reload the plugin on save. For changes that a rescan won't pick up — a
`keepLoaded` component that is already instantiated — use `omarchy-restart-shell`.

> Remove this dev install with `rm ~/.config/omarchy/plugins/omaseek`.
> Do **not** use `omarchy plugin remove`, which would delete through the symlink.

Run `./bin/test` after touching anything in `src/lib`.

Logs: `journalctl -t omarchy-shell -f`.

## Not implemented

The vim layer stops short of `.` repeat, macros, marks, named registers, and
line-wise visual mode — a single-line field gets little from them.
