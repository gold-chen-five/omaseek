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

The last twenty-five queries are kept in `~/.local/share/omaseek/queries.json`:
the search field is one line, so `↑` and `↓` walk them the way a shell does, and
`↓` past the newest puts back what you were typing before stepping into the
results.

The last ten conversations are kept in `~/.local/share/omaseek/sessions.json`
and survive a shell restart. A strip of numbered squares under the status line
shows them, `1` the newest and the open one filled: click one to switch, or
walk them with `ctrl+n`. `ctrl+x` forgets the one on screen, and the `+` square
(or `ctrl+c`) starts another. `ctrl+c` while the agent is still thinking leaves
that question running — its square keeps a dot until the answer lands in it —
so you can start something else and come back to a finished reply. `q` or `esc`
in normal mode stops a reply instead, keeping the conversation and the words so far, and
`ctrl+shift+r` asks the last question again after a stop or a failure — the
`chat` button turns into `stop` and `retry` for the same.

Each result names the SearXNG engines that found it. **Ctrl+S → Search** switches
Brave, Bing and Google on and off, picks the language and region, and **Test**
runs a real query to show how long it took and which engines answered. A next
page that fails to load says `page failed · l retries` rather than pretending
the results ended.

Replies appear as they are written, where the agent's CLI streams them
(Claude Code does; the others answer whole). **Ctrl+S → Ask** turns it off.

[**KEYS.md**](KEYS.md) has every binding. `ctrl+s` opens settings, which
writes `~/.config/omaseek/config.json`.

## Install

```bash
git clone git@github.com:gold-chen-five/omaseek.git ~/.config/omarchy/plugins/omaseek
~/.config/omarchy/plugins/omaseek/bin/install
```

The checkout *is* the installed plugin — that is where Omarchy looks, and the
shape [its plugin docs](https://plugins.omarchy.org/develop.html) describe.

Omarchy then enables a plugin by recording its id and nothing else: it never
runs a script from a plugin and never edits your Hyprland or menu config, so
the keybind cannot come with the download. `./bin/install` is the opt-in way
to add it — it enables the plugin, binds `SUPER + D`, and adds a small search
icon to the middle of the bar. It is safe to re-run and leaves
`SUPER + D` alone if you have already bound it to something else. On an
upgrade, it removes only the menu row written by the previous installer.
`--no-bind` skips the keybind.

By hand instead:

```bash
omarchy-shell shell rescanPlugins
omarchy bar put omaseek --section center --index 0
```

then in `~/.config/hypr/bindings.lua`, followed by `hyprctl reload`:

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

Searching needs a SearXNG instance you run yourself — `./bin/searxng-up`
creates one on port 8888, and the panel offers to start it when it is down.
**Ctrl+S → Search → Update SearXNG** pulls the latest image and replaces the
container only when it changed; the existing configuration is kept.
Asking uses an agent CLI you already have (`claude`, `codex`, `gemini`,
`hermes`, …); there is no API key.

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
