# omaseek

A web search and AI panel for [Omarchy](https://omarchy.org) 4, driven with
vim keys. **SUPER + D** to summon it, **Tab** to switch between searching the
web and asking an agent.

It runs as a plugin inside the existing `omarchy-shell` Quickshell process, so
it opens instantly and follows the active Omarchy theme with no configuration
of its own. Searches go through a SearXNG instance you run yourself; the AI
half talks to agent CLIs you already have installed — there is no API key.

## Install

```bash
git clone git@github.com:gold-chen-five/omaseek.git
ln -s "$PWD/omaseek" ~/.config/omarchy/plugins/omaseek
omarchy-shell shell rescanPlugins
omarchy plugin enable omaseek
```

Bind it in `~/.config/hypr/bindings.lua`, then `hyprctl reload`:

```lua
o.bind("SUPER + D", "Search", "omarchy-shell shell toggle omaseek")
```

Searching needs a SearXNG instance. `./bin/searxng-up` creates one in Docker
on port 8888 and is safe to re-run; the panel offers to start it for you when
it finds it down. SearXNG ships with its JSON API off, so `settings.yml` needs
`json` under `search.formats` — the setup script does this for a container it
creates.

## Keys

[**KEYS.md**](KEYS.md) is the full list. The short version:

| key | does |
|---|---|
| `super+d` | summon or dismiss |
| `tab` | switch between search and ask |
| `enter` | search, or ask |
| `j` / `k` | step into and through the results |
| `enter` on a result | open it in the browser |
| `h` / `l` | previous and next page |
| `v` / `V`, `y` | select in an answer, and yank |
| `enter` on a selection | hand it to the agent in a terminal |
| `ctrl+c` | new chat |
| `ctrl+s` | settings |
| `esc` | back, then out |

The search field is vim on one line: motions, operators, counts and text
objects (`diw`, `ci"`, `da(`). `jk` leaves insert.

## Settings

`ctrl+s`, or edit `~/.config/omaseek/config.json` — the panel writes only the
keys it owns and leaves the rest alone.

| key | default | what it is |
|---|---|---|
| `searxng_url` | `http://localhost:8888` | your instance |
| `searxng_engines` | *(unset)* | which engines to ask, by SearXNG name |
| `results_per_page` | `10` | every page shows this many |
| `chat_agent` | `default` | `omarchy default agent`, or one id |
| `launcher` | `terminal` | where a hand-off opens: `terminal`, `tmux`, `herdr` |
| `escape_sequence` | `jk` | leaves insert |
| `search_key` | `enter` | runs the query |
| `new_chat_key` | `ctrl+c` | starts a new conversation |

`searxng_engines` is the one worth setting. SearXNG waits for every engine in
the category, so one slow engine sets the pace for all of them. Naming the few
that actually answer took a query from ~1.1s to ~0.3s here:

```json
"searxng_engines": ["brave", "google cse", "wikipedia"]
```

## How it works

Two small programs, each printing one JSON object and exiting 0 even when they
fail, so a handled failure is still a well-formed answer:

- `bin/search` — one request per page from SearXNG. Pages are sliced from a
  session buffer under `~/.cache/omaseek/`, because a SearXNG page is however
  many engines answered in time, and results are de-duplicated on URL and on
  domain+title.
- `bin/ask` — one turn through an agent CLI's print mode (`claude`, `codex`,
  `opencode`, `gemini`, `hermes`, `copilot`, `cursor-agent`). Print mode
  remembers nothing, so the conversation lives in the panel and travels in the
  prompt. When an agent is signed out or unconfigured, the panel hands the
  sign-in to a terminal with your question chained behind it.

Everything that is a pure function of its inputs lives in `src/lib` as an ES
module and runs under node's test runner; everything needing Qt stays in QML.

## Development

No build step, no dependencies — Python is stdlib-only and the JS is plain ES
modules.

```bash
./bin/test                                       # unit tests
./bin/dev-watch                                  # reload on save
omarchy-restart-shell                            # when a keepLoaded component is already live
quickshell log -p /usr/share/omarchy/shell -f    # QML errors and console.log
```

The repo is symlinked into the plugins directory, so remove a dev install with
`rm ~/.config/omarchy/plugins/omaseek` — **not** `omarchy plugin remove`, which
would delete through the symlink.

## Not implemented

The vim layer stops short of `.` repeat, macros, marks, named registers and
line-wise visual — a single-line field gets little from them.

## License

MIT
