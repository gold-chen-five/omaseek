# omaseek

A web search and AI panel for [Omarchy](https://omarchy.org) 4, driven with vim keys.

**SUPER + D** to summon it. **Tab** switches between searching the web and asking an agent.

| key | does |
|---|---|
| `super+d` | summon or dismiss |
| `tab` | search ⇄ ask, keeping the current Vim mode |
| `enter` | search and focus the first result, or ask |
| `↑` `↓` | in the search field: the queries you searched before |
| `j` `k` | through the results |
| `enter` on a result | open it in the browser |
| `h` `l` | previous and next page |
| `v` `V` then `y` | select in an answer, and yank |
| `enter` on a selection | hand it to the agent in a terminal |
| `/` `?` then `n` `N` | search the results or the answer |
| `*` `#` | search for the word under the cursor, in an answer |
| `y` on a result | copy its URL |
| `gc` `gs` | ask about the result, or search for the selection |
| `ctrl+c` | new session, keeping this one |
| `ctrl+n` `ctrl+x` | the next saved session, or forget this one |
| `ctrl+shift+x` | forget every saved session (press twice) |
| `ctrl+s` | settings |
| `esc` | back, then out |

The field is vim on one line — motions, operators, counts, text objects
(`diw`, `ci"`, `da(`). `jk` leaves insert. In the results and the answer, `/`
searches the pane and `gi` or `gn` go back to the field, typing or in normal
mode.

Paste an address into the search field and Enter opens it in the browser, the
way an address bar would; `gx` in normal mode opens the one under the cursor.
`gs` on a result searches for its title.

The last twenty-five queries are kept in `~/.local/share/omaseek/queries.json`:
the search field is one line, so `↑` and `↓` walk them the way a shell does, and
`↓` past the newest puts back what you were typing before stepping into the
results.

The last ten conversations are kept in `~/.local/share/omaseek/sessions.json`
and survive a shell restart. A strip of numbered squares under the status line
shows them — it appears once the first question has been asked, so a fresh
install shows none — `1` the newest and the open one filled: click one to switch, or
walk them with `ctrl+n`. `ctrl+x` forgets the one on screen, and the `+` square
(or `ctrl+c`) starts another. `ctrl+c` while the agent is still thinking leaves
that question running — its square keeps a dot until the answer lands in it —
so you can start something else and come back to a finished reply. `q` or `esc`
in normal mode stops a reply instead, keeping the conversation and the words so far, and
`ctrl+shift+r` asks the last question again after a stop or a failure — the
`chat` button turns into `stop` and `retry` for the same.

Each result names the SearXNG engines that found it. **Ctrl+S → Search** switches
Google CSE, Bing, Brave (the defaults) and Google on and off, picks the language and region, and **Test**
runs a real query to show how long it took and which engines answered. A next
page that fails to load says `page failed · l retries` rather than pretending
the results ended.

Replies appear as they are written, where the agent's CLI streams them
(Claude Code does; the others answer whole). **Ctrl+S → Ask** turns it off.

[**KEYS.md**](KEYS.md) has every binding. `ctrl+s` opens settings, which
writes `~/.config/omaseek/config.json`.

## Install

omaseek is an Omarchy 4 plugin. It is not listed in the Omarchy plugin
marketplace yet, so add it from its repository with Omarchy's own plugin
command:

```bash
omarchy plugin add https://github.com/gold-chen-five/omaseek.git --enable
```

Omarchy clones it into `~/.config/omarchy/plugins/omaseek`, validates the
manifest, enables it, and asks which bar section gets the search icon (center
by default). Review the code before enabling it: like every Omarchy plugin,
omaseek runs unsandboxed inside `omarchy-shell`.

### Keybind

A plugin cannot bind keys, since Omarchy never edits your Hyprland config for
one. Add this line to `~/.config/hypr/bindings.lua`, then run `hyprctl reload`:

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

Or let the plugin's helper add it. It appends that line with a backup, and
leaves `SUPER + D` alone if you have already bound it to something else:

```bash
~/.config/omarchy/plugins/omaseek/bin/install
```

Without a keybind, the bar icon opens the panel.

### SearXNG

Searching needs a SearXNG instance you run yourself. The first time you search,
the panel offers to create one, or you can run:

```bash
~/.config/omarchy/plugins/omaseek/bin/searxng-up
```

It runs the `searxng/searxng` Docker image as a container named `searxng`,
listening on `127.0.0.1:8888` only, and writes `~/.config/searxng/settings.yml`
with the JSON API on. **Ctrl+S → Search → Update SearXNG** shows the running
version, pulls a newer image and replaces the container only when it changed.
The configuration is kept.

Asking uses an agent CLI you already have (`claude`, `codex`, `crush`,
`opencode`, `gemini`, `hermes`, `copilot`, `cursor-agent`); there is no API key.

## Update

```bash
omarchy plugin update omaseek
omarchy-restart-shell
```

The panel stays loaded between summons, so it keeps the old code until the
shell restarts.

## Uninstall

```bash
omarchy plugin remove omaseek
```

**Remove Plugin** in the Omarchy menu does the same. As omaseek is removed, a
terminal opens and asks whether the SearXNG Docker container and image should
go too; `~/.config/searxng` is kept either way. Disabling the plugin or
restarting the shell asks nothing, and a plugin that was already disabled
before removal cannot ask, because it is no longer loaded.

`bin/uninstall` does the same from a terminal you already have open, and also
removes the `SUPER + D` line `bin/install` added. `--searxng` or
`--keep-searxng` answers the SearXNG question in advance, and `--yes` skips the
one about the plugin.

Left behind for you to delete: `~/.config/omaseek` (settings),
`~/.local/share/omaseek` (queries and conversations), `~/.cache/omaseek`, and
`~/.config/searxng`.

## Dependencies and privileges

| needs | for |
|---|---|
| Omarchy 4 (`omarchy-shell`, `gum`, `xdg-terminal-exec`) | the panel, and terminals for setup and removal |
| `python3` (standard library only) | `bin/search` and `bin/ask` |
| Docker | the SearXNG container (the image is pulled from Docker Hub) |
| an agent CLI, optional | asking; the agent's own sign-in and provider |
| `tmux` or `herdr`, optional | hand-offs to a tmux window or a herdr tab instead of a terminal |
| `jq` | `bin/install` |

What it does outside the panel:

- **sudo**: `bin/searxng-up` alone uses it, always in a visible terminal. It
  runs `sudo systemctl enable --now docker` when the Docker daemon is not running,
  and `sudo docker …` when you are not in the `docker` group. Nothing else asks
  for privileges.
- **Network**: searches go to your SearXNG, which queries the engines you
  enable (Google CSE, Bing and Brave by default). Result icons come from
  DuckDuckGo's favicon service (`external-content.duckduckgo.com/ip3/`), which
  is sent each result's bare domain and never your query. Settings asks Docker Hub for
  the SearXNG image's tags to say whether an update exists. Questions go to
  whichever agent CLI you use, and on to its provider. There is no telemetry.
- **Files**: settings in `~/.config/omaseek/config.json`, history in
  `~/.local/share/omaseek/`, the page cache in `~/.cache/omaseek/`, SearXNG's
  config in `~/.config/searxng/`, and a copy of the removal scripts in
  `$XDG_RUNTIME_DIR/omaseek-removal/`. Your Hyprland config is edited only by
  `bin/install` and `bin/uninstall`, when you run them, with a backup.
- **Agent hand-offs** (`ga`, `gA`, sign-in) open the agent's interactive CLI
  with the same auto-approve flags `omarchy-agent` uses (`claude --permission-mode
  auto`, `codex --approve-for-me`, `gemini --yolo`, …). The prompt is pasted as
  an editable draft and never submitted for you. Links open only for `http` and
  `https`.

## Switch AI models

Open **Ctrl+S → Ask**, choose your **Agent**, then open the **Model** dropdown
with **Enter**. Use **j/k** or **↑/↓** to choose and **Enter** to save, exactly
like the Agent dropdown. Choose **default** to use the CLI's own model choice.

OpenCode, Cursor and Copilot supply their model lists through their CLIs; Codex
uses its local model catalogue. Omaseek does not carry its own model list: when
an agent cannot report one, or lookup fails, the dropdown contains only
**default**. Model access depends on the agent's configured provider and account.

The choice is remembered separately for each agent, including the resolved
agent when **Agent** is `default`. It applies to the next question in the current
conversation and to terminal/tmux/herdr hand-offs. A reply already running
finishes with its original model.

These choices live under `chat_models` in `~/.config/omaseek/config.json`.
For a one-off backend call, pass `"model"` in the `./bin/ask --json` payload;
an empty string uses the CLI default.

## License

MIT
