# jonas.search — Omarchy web search panel

A keybind-summoned DuckDuckGo search overlay for Omarchy 4, with vim keybindings.
Runs as a plugin inside the existing `omarchy-shell` Quickshell process, so it
opens instantly and follows the active Omarchy theme with no configuration.

## Usage

Press **SUPER + D**.

### Search bar

| Key | Action |
|---|---|
| *(type)* | build the query |
| `Enter` | run the search, jump straight to results |
| `Esc` | leave INSERT for NORMAL mode |
| `jk` | the same, without reaching for Esc |
| `j` / `↓` (in NORMAL) | step down into the results |
| `Esc` (in NORMAL) | close the panel |
| `Ctrl+W` / `Ctrl+U` | delete word back / to start (insert mode) |

From NORMAL mode the result list is simply the line below, so `j` moves into
it — the panel reads as one vertical buffer rather than two separate widgets.

`jk` is vim's `inoremap jk <Esc>` in miniature: the `j` types as normal and is
taken back when the `k` lands within 200 ms. Type the two keys further apart
than that and they stay text, which is how a query that genuinely contains
`jk` still works. Both the sequence and the window are yours to set in
`~/.config/jonas.search/config.json`:

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

## How it works

```
manifest.json          plugin manifest — overlay kind, keepLoaded for instant summon
src/
  Search.qml           entry point: layer-shell window, focus machine, wiring
  components/
    VimTextField.qml   the vim mode machine and key dispatch
    ResultList.qml     the list and its cursor
    ResultRow.qml      one result: favicon, title, domain, snippet
    StatusLine.qml     mode on the left, search state on the right
  lib/
    motions.mjs        pure cursor motions
    keymap.mjs         the insert-mode escape sequence and its config
    search.mjs         result merging, error and status strings
bin/
  search               DuckDuckGo client with Exa fallback — stdlib Python
  dev-watch.sh         hot reload during development
  test                 runs the unit tests
test/                  node tests for src/lib
```

The split follows one rule: anything that is a pure function of its inputs
lives in `src/lib` as an ES module, and everything that needs Qt stays in QML.
`.mjs` modules load in both QML (`import "lib/motions.mjs" as Motions`) and
node, so the cursor arithmetic and the paging rules are tested directly:

```bash
./bin/test          # 41 tests, no shell and no network
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

It distinguishes a network failure, a rebuffed request, and a genuinely empty
result set, so the panel never reports "no results" when it was actually blocked.

Pagination is not a simple offset — DuckDuckGo ignores a bare `s` parameter and
only serves the next page when the *entire* hidden nav form is echoed back
(`vqd`, `kl` and `nextParams` included). So `next` in the JSON carries that form
verbatim and comes back in as `--next '<json>'`:

```bash
./bin/search --next "$(./bin/search rust | jq -c .next)" | jq '.results[0]'
```

Because each search is its own process, the client keeps a cookie jar at
`~/.cache/jonas.search/cookies.txt` so a run of queries reads as one session
rather than a stream of cookieless strangers.

### Exa fallback

DuckDuckGo needs no key but blocks under load. When it does, the query falls
through to **Exa's MCP endpoint** (`mcp.exa.ai/mcp`), which answers without an
API key — so the fallback needs no configuration at all. The status line shows
`· via Exa` so a swapped engine is never silent.

This is the same endpoint [opencode](https://github.com/anomalyco/opencode)
uses, and it is why its web search costs nothing:

```ts
export const EXA_URL = process.env.EXA_API_KEY
  ? `https://mcp.exa.ai/mcp?exaApiKey=${...}`
  : "https://mcp.exa.ai/mcp"
```

There is no API key and no configuration. Exa's metered API (`api.exa.ai`,
$7 per 1,000 searches) is a separate product this deliberately does not use,
so nothing here can ever bill you.

> The keyless endpoint is undocumented and carries no guarantee. It could gain
> auth or rate limits at any time — it is a fallback, not a foundation.

### Uniform pages

Engines disagree about page size. DuckDuckGo returns 10 results for the first
request and 15 for every offset after it; Exa returns one batch of 30 and has
no offset parameter at all. Paging straight off either would give ragged pages.

So neither is paged directly. Whatever a chunk contains is accumulated in a
session buffer under `~/.cache/jonas.search/`, and pages are sliced from that
at a fixed size — every page holds 10, except the last.

That also means fewer requests: a 15-result fetch covers one and a half pages,
paging backwards costs nothing, and a page turn tops the buffer up at most
three times so it can never burst. Rows are de-duplicated on URL *and* on
domain+title as they land, because engines repeat hits across page boundaries
and Exa returns the same document under several canonical paths (`/book/` and
`/stable/book/`).

The buffer is read only while paging. Pressing Enter always searches afresh.

### Rate limiting

DuckDuckGo will serve an anti-bot challenge ("select all squares containing a
duck") if it sees too many requests too quickly, and the block lasts a while.
Normal launcher use is nowhere near that threshold, but paging pulls a request
per page, so holding `j` through many pages is the way to find the limit. When
it happens the panel says so plainly instead of pretending there were no
results.

## Install

```bash
ln -s /mnt/hdd/work/qml ~/.config/omarchy/plugins/jonas.search
omarchy-shell shell rescanPlugins
omarchy plugin enable jonas.search
```

Then add the keybind to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Web search", "omarchy-shell shell toggle jonas.search")
```

and `hyprctl reload`.

## Development

The repo lives outside `~/.config/omarchy/plugins/` and is symlinked in.
Omarchy's hot-reload watcher (`inotifywait -r`) does not follow symlinks, so run:

```bash
./bin/dev-watch.sh
```

to reload the plugin on save. For changes that a rescan won't pick up — a
`keepLoaded` component that is already instantiated — use `omarchy-restart-shell`.

> Remove this dev install with `rm ~/.config/omarchy/plugins/jonas.search`.
> Do **not** use `omarchy plugin remove`, which would delete through the symlink.

Run `./bin/test` after touching anything in `src/lib`.

Logs: `journalctl -t omarchy-shell -f`.

## Not implemented

The vim layer stops short of `.` repeat, macros, marks, named registers, and
line-wise visual mode — a single-line field gets little from them.
