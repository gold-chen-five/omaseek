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
| `Esc` (in NORMAL) | close the panel |
| `Ctrl+W` / `Ctrl+U` | delete word back / to start (insert mode) |

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
| `j` / `k`, `↓` / `↑` | move the cursor |
| `gg` / `G` | first / last result |
| `Ctrl+D` / `Ctrl+U` | half-page down / up |
| `Enter` | open the highlighted result in the browser |
| `i` or `/` | back to the search bar (INSERT) |
| `Esc` | back to the search bar (NORMAL) |

Results open with `omarchy-launch-browser`, which respects your default browser.

## How it works

| File | Role |
|---|---|
| `manifest.json` | plugin manifest — `overlay` kind, `keepLoaded` for instant summon |
| `Search.qml` | layer-shell window, focus state machine, backend wiring |
| `VimTextField.qml` | the vim editing model over `qs.Ui.TextField` |
| `ResultList.qml` | result rows and the selection cursor |
| `bin/ddg-search` | DuckDuckGo client — stdlib Python, JSON on stdout |
| `bin/dev-watch.sh` | hot reload for development (see below) |

Theming is inherited: the panel paints with the `[menu]` surface tokens from
`qs.Commons` (`Color.menu.*`, `Style.*`), the same ones Omarchy's own overlays
use, so every theme and light/dark switch applies automatically.

`bin/ddg-search` is deliberately a separate process rather than QML JavaScript.
HTML parsing is the fragile part, and this keeps it testable on its own:

```bash
./bin/ddg-search "python asyncio" | jq
```

It distinguishes a network failure, a rebuffed request, and a genuinely empty
result set, so the panel never reports "no results" when it was actually blocked.

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

Logs: `journalctl -t omarchy-shell -f`.

## Not implemented

The vim layer stops short of `.` repeat, macros, marks, named registers, and
line-wise visual mode — a single-line field gets little from them.
