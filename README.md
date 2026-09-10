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
| `ctrl+c` | new chat |
| `ctrl+s` | settings |
| `esc` | back, then out |

The field is vim on one line — motions, operators, counts, text objects
(`diw`, `ci"`, `da(`). `jk` leaves insert.

[**KEYS.md**](KEYS.md) has every binding. `ctrl+s` opens settings, which
writes `~/.config/omaseek/config.json`.

## Install

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/omaseek
omarchy-shell shell rescanPlugins
omarchy plugin enable omaseek
```

Bind it in `~/.config/hypr/bindings.lua`, then `hyprctl reload`:

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

Searching needs a SearXNG instance you run yourself — `./bin/searxng-up`
creates one on port 8888, and the panel offers to start it when it is down.
Asking uses an agent CLI you already have (`claude`, `codex`, `gemini`,
`hermes`, …); there is no API key.

## License

MIT
