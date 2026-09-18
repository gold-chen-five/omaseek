# omaseek

A web search and AI panel for [Omarchy](https://omarchy.org) 4, driven with vim
keys. It searches through a SearXNG instance you run yourself and asks an agent
CLI you already have — no API keys, no accounts.

**SUPER + D** summons it. **Tab** switches between searching and asking.

## Install

```bash
omarchy plugin add https://github.com/gold-chen-five/omaseek.git --enable
```

Not in the Omarchy plugin marketplace yet, hence the repository URL. Plugins run
unsandboxed inside `omarchy-shell`, so read the code before enabling it.

**The keybind.** A plugin cannot edit your Hyprland config, so add this to
`~/.config/hypr/bindings.lua` and run `hyprctl reload` — or run
`~/.config/omarchy/plugins/omaseek/bin/install`, which appends it with a backup
and leaves `SUPER + D` alone if you have already bound it. The bar icon opens
the panel either way.

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

**SearXNG.** Searching needs one. The panel offers to create it the first time
you search, or run `bin/searxng-up`: it starts the `searxng/searxng` Docker
image on `127.0.0.1:8888` and writes `~/.config/searxng/settings.yml` with the
JSON API on.

**Asking** uses whichever agent CLI you have — `claude`, `codex`, `crush`,
`opencode`, `gemini`, `hermes`, `copilot`, `cursor-agent`.

## Keys

| key | does |
|---|---|
| `super+d` | summon or dismiss |
| `tab` | search ⇄ ask |
| `enter` | search, or ask |
| `j` `k` | through the results; `enter` opens one |
| `h` `l` | previous and next page; `3h` `5l` walk several, `5gp` jumps to page 5 |
| `y` `Y` | copy a result's URL, or its title with it |
| `v` `V` then `y` | select in an answer and copy |
| `/` `?` `n` `N` | search the results or the answer |
| `ga` `gA` | hand off to the agent in a terminal: this result, or everything |
| `gc` `gs` | ask about a result or a selected passage, or search for a selection |
| `ctrl+c` `ctrl+n` `ctrl+x` | a new conversation, the next saved one, forget this one |
| `L` `H` | in ask mode: the next saved conversation, or the one before |
| `ctrl+s` | settings |
| `esc` | back, then out |

The field is vim on one line — motions, operators, counts, text objects
(`diw`, `ci"`, `da(`), and `jk` to leave insert. `↑` `↓` walk the last
twenty-five queries. Paste an address and `enter` opens it.

Under the status line, numbered squares are the pages you have read: click one
to go back, or `›` to fetch the next. Ask mode gets the same strip for its last
ten conversations, which survive a restart.

[**KEYS.md**](KEYS.md) has every binding, and settings can move any of them.

## Settings

`ctrl+s`, saved as you go to `~/.config/omaseek/config.json`.

- **Search** — start or stop SearXNG, update its image, language and region,
  results per page.
- **Ask** — the agent, its model, streaming, and where a hand-off opens.
- **Display** — line numbers and page numbers, relative or absolute.
- **Keys** — every binding.
- **Engines** — which engines SearXNG asks: Google CSE, Bing, Brave and
  DuckDuckGo by default, plus Google, Startpage, Yep, Yandex and Yahoo.
  **Search speed** times one real search; **Test engines** asks each one alone
  and says what it gave, or why it refused.

## Update

```bash
omarchy plugin update omaseek
omarchy-restart-shell     # a loaded panel keeps its old code until then
```

## Uninstall

```bash
omarchy plugin remove omaseek
```

A terminal opens and asks whether the SearXNG container and image should go
too. `bin/uninstall` does the same from a terminal you already have open, and
also removes the keybind `bin/install` added.

Left for you to delete: `~/.config/omaseek`, `~/.local/share/omaseek`,
`~/.cache/omaseek` and `~/.config/searxng`.

## Requirements, and what it touches

| needs | for |
|---|---|
| Omarchy 4 (`omarchy-shell`, `gum`, `jq`, `xdg-terminal-exec`) | the panel, and terminals for setup and removal |
| `python3`, standard library only | `bin/search` and `bin/ask` |
| Docker | the SearXNG container |
| an agent CLI, optional | asking |
| `tmux` or `herdr`, optional | hand-offs somewhere other than a terminal |

- **sudo** — `bin/searxng-up` alone, always in a terminal you can watch:
  `systemctl enable --now docker` when the daemon is down, and `sudo docker`
  when you are not in the `docker` group.
- **Network** — your SearXNG and the engines you enable; DuckDuckGo's favicon
  service, sent each result's bare domain and never your query; Docker Hub, for
  whether a newer SearXNG image exists; your agent CLI's own provider. No
  telemetry.
- **Files** — `~/.config/omaseek`, `~/.local/share/omaseek`, `~/.cache/omaseek`,
  `~/.config/searxng`, and removal scripts under `$XDG_RUNTIME_DIR`. Your
  Hyprland config is touched only by `bin/install` and `bin/uninstall`, with a
  backup.
- **Hand-offs** open the agent's interactive CLI with the same auto-approve
  flags `omarchy-agent` uses. The prompt waits there as an editable draft;
  nothing is submitted for you.

## License

MIT
