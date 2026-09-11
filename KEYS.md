# Keys

Every binding in the panel, by the view that owns it. Written flat and
greppable because it is read as often by an agent as by a person — if you
change a key, change it here in the same commit.

Two of these are rebindable in settings and stored in
`~/.config/omaseek/config.json`; everything else is fixed in the source.

| setting | config key | default | what it does |
|---|---|---|---|
| Leave insert with | `escape_sequence` | `jk` | typed within vim's timeoutlen, leaves insert |
| Search | `search_key` | `enter` | runs the query — the button beside the field |
| New session | `new_session_key` | `ctrl+c` | forgets the conversation and starts one |

A binding is written the way a person says it: a named key (`enter`, `esc`,
`tab`, `space`, an arrow, `home`, `end`), a single character, or `ctrl+`
either of those. Anything else is refused and the previous value stands.

## Anywhere in the panel

| key | does |
|---|---|
| `super+d` | summon or dismiss (Hyprland, not the panel — `omarchy-shell shell toggle omaseek`) |
| `ctrl+s`, `ctrl+,` | open or close settings |
| `tab` | switch between searching and asking |
| `esc` | leave: normal mode from insert, the field from a list, the panel from the field |

## The field

Insert mode:

| key | does |
|---|---|
| `jk` (the escape sequence) | to normal mode |
| `ctrl+w` | delete the word before the cursor |
| `ctrl+u` | delete to the start of the line |
| `ctrl+j` | a line break in a question: shown as `↵`, sent as a newline |
| `down` | step into the results or the transcript |
| `enter` (the search key) | search, or ask; the field drops to normal, so `j` steps into what came back |

Normal mode is vim, on one line: `h l w W b B e 0 ^ $`, `f F t T{char}`,
`i a I A`, `x`, `d c y` with a motion or doubled (`dd cc yy`), `p P`, `v`,
counts (`3w`, `2dw`), and text objects (`diw`, `ci"`, `da(`). `j` or `down`
steps into what is below. Deliberately absent: `.` repeat, macros, marks,
named registers, linewise visual — a single-line field gains little from
them.

## The results

| key | does |
|---|---|
| `j` `k`, `down` `up` | move the cursor |
| `ctrl+d` `ctrl+u` | half a screen |
| `gg` `G` | first, last |
| `l` `right` | next page |
| `h` `left` | previous page |
| `enter` | open in the browser and dismiss |
| `i`, `/` | back to the field, typing |
| `esc` | back to the field, normal mode |

## The answer

| key | does |
|---|---|
| `j` `k` `h` `l`, arrows | move the cursor by line and character |
| `w` `W` `b` `B` `e` `E` | by word |
| `0` `^` `home`, `$` `end` | line ends |
| `gg` `G` | transcript ends |
| `ctrl+d` `ctrl+u` | half a screen |
| `v` | select by character |
| `V` | select by line |
| `gv` | reselect what was last selected |
| `y` | yank the selection, or the whole transcript |
| `gx` | open the link under the cursor — or, in visual mode, the selected URL — in the browser; http and https only, a bare domain gets `https://` |
| `enter` | hand the selection to the agent in a terminal |
| `ctrl+c` (the new-session key) | start a new conversation |
| `i`, `/` | back to the field, typing |
| `esc` | drop the selection, else back to the field |

## Settings

| key | does |
|---|---|
| `j` `k` | move between rows, stepping over section headings |
| `h` `l` | change the value under the cursor; on the SearXNG switch, off and on |
| `enter`, `i` | open a typed row for editing, flip the SearXNG switch, or open a dropdown |
| `gg` `G` | first, last row |
| `enter` while editing | commit |
| `esc` while editing | cancel |
| `j` `k`, `enter`, `esc` in an open dropdown | walk it, pick, close |
| `esc`, `ctrl+s` | back to the panel |

Values are written as they change; there is no save.

## The setup prompt

| key | does |
|---|---|
| `h` `l`, arrows, `tab` | choose |
| `enter` | confirm |
| `esc` | not now |

## Where they live in the source

- `src/lib/keys.mjs` — the tables for the two panes that are *read* (results, answer), chord → command name
- `src/lib/keybinds.mjs` — the rebindable chords: `"ctrl+c"` ↔ `"C-c"`
- `src/components/chord.js` — Qt key events → chord strings
- `src/components/VimTextField.qml` — the field's mode machine and everything vim
- `src/components/ResultList.qml`, `AnswerView.qml`, `SettingsPage.qml`, `SetupPrompt.qml` — each view's own dispatch
