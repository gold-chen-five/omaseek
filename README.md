# omaseek

A web search and AI panel for [Omarchy](https://omarchy.org) 4, driven with vim keys.

**SUPER + D** to summon it. **Tab** switches between searching the web and asking an agent.

| key | does |
|---|---|
| `super+d` | summon or dismiss |
| `tab` | search ⇄ ask |
| `enter` | search, or ask |
| `j` `k` | into and through the results |
| `enter` on a result | open it in the browser |
| `h` `l` | previous and next page |
| `v` `V` then `y` | select in an answer, and yank |
| `enter` on a selection | hand it to the agent in a terminal |
| `ctrl+c` | new session |
| `ctrl+s` | settings |
| `esc` | back, then out |

The field is vim on one line — motions, operators, counts, text objects
(`diw`, `ci"`, `da(`). `jk` leaves insert.

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
to add it — it enables the plugin, binds `SUPER + D`, and adds a row to the
Omarchy menu. It is safe to re-run, backs up what it touches, and leaves
`SUPER + D` alone if you have already bound it to something else. `--no-bind`
and `--no-menu` skip either half.

By hand instead:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable omaseek
```

then in `~/.config/hypr/bindings.lua`, followed by `hyprctl reload`:

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

Searching needs a SearXNG instance you run yourself — `./bin/searxng-up`
creates one on port 8888, and the panel offers to start it when it is down.
Asking uses an agent CLI you already have (`claude`, `codex`, `gemini`,
`hermes`, …); there is no API key.

## License

MIT
