# Keys

Every binding in the panel, by the view that owns it. Written flat and
greppable because it is read as often by an agent as by a person — if you
change a key, change it here in the same commit.

Settings → Keys rebinds every key below that has a name in the first column,
and Settings → Fixed keys lists the rest, so the page doubles as the answer
to "what can I press". Changes are saved in `~/.config/omaseek/config.json`.

| setting | config key | default | what it does |
|---|---|---|---|
| Leave insert with | `escape_sequence` | `jk` | typed within vim's timeoutlen, leaves insert |
| Search / ask | `search_key` | `enter` | field: runs the query or asks the question |
| New session | `new_session_key` | `ctrl+c` | field and answer: forget the conversation and start one |
| Next session | `next_session_key` | `ctrl+n` | ask: the next saved conversation, newest first, wrapping |
| Close session | `close_session_key` | `ctrl+x` | ask: forget this conversation and show the one below it |
| Delete all sessions | `clear_sessions_key` | `ctrl+shift+x` | ask: forget every saved conversation, on the second press |
| Settings | `settings_key` | `ctrl+s` | anywhere: open or close settings (`ctrl+,` always works too) |
| Switch search / ask | `switch_mode_key` | `tab` | anywhere, without changing Vim mode (`shift+tab` always works too) |
| Open | `open_key` | `enter` | results: open the result and dismiss · answer: the link under the cursor or in the selection |
| Hand off to agent | `handoff_key` | `ga` | results: the selected result's URL, alone · answer: the selection, else the reply under the cursor with its question |
| Hand off everything | `handoff_all_key` | `gA` | results: every URL on the page · answer: the whole conversation |
| Open link | `open_link_key` | `gx` | answer: the URL under the cursor or in the selection |
| Next page | `next_page_key` | `l` | results (`right` always works too) |
| Previous page | `previous_page_key` | `h` | results (`left` always works too) |
| Back to the field | `insert_key` | `gi` | results and answer: return to the field in normal mode (`/` always works) |

A hand-off opens the agent (Settings → Ask → Hand off to) with the text
pasted into its input and not sent: edit it, then submit it yourself.

The last ten AI conversations are kept, newest first, in
`~/.local/share/omaseek/sessions.json`. Every turn is saved as it happens, so
they survive a shell restart; `ctrl+n` walks them from the field or the answer
(from a conversation that has not been asked yet, it lands on the newest),
`ctrl+x` forgets the one on screen and shows the one below it, and `ctrl+c`
leaves it in the ring and starts an empty one. The eleventh conversation drops
the oldest. A strip of numbered squares under the status line shows them —
`1` is the newest, the one on screen is filled, hovering names it, and clicking
one opens it; the last square, `+`, starts a new conversation and is filled
while the live one has nothing saved of it yet. The status line says the same in
words — `session 2/3`.

**A question keeps being answered after you leave it.** `ctrl+c` while the agent
is thinking opens a new conversation and lets the old one finish: its square
keeps a pulsing dot until the reply lands, and the reply lands in *that*
conversation, so `ctrl+n` back to it shows the finished answer. You can ask in
the new conversation straight away — each question has its own agent process.
`ctrl+x` is the one key that does cancel: closing a conversation stops the
question nobody will read, and `ctrl+shift+x` forgets every saved conversation
at once — it cannot be undone, so the status line asks for a second press and
any other session key calls it off. A question you leave that was never sent anywhere —
no answer, nothing running — is dropped rather than left as an empty square.

A binding is written the way a person says it: a named key (`enter`, `esc`,
`tab`, `space`, an arrow, `home`, `end`), one character — case matters, `G`
is not `g` — or `ctrl+` a key, optionally with `shift+` after it
(`ctrl+shift+x`). Shift on its own is not a modifier here: `X` already spells
it. Keys for the results and the answer may also
be two keys in turn: `gx`, `gA`, or `g x`. Search, new session, settings and
switch are caught before the field types anything, so they must be a named
key or a ctrl chord. The page refuses a key that is none of these, or that
another action or a fixed key already uses — `gg`, or `g` alone, which would
swallow it — and says which under the label; the previous value stands. An
empty value restores the default.

## Anywhere in the panel

| key | does |
|---|---|
| `super+d` | summon or dismiss (Hyprland, not the panel — `omarchy-shell shell toggle omaseek`) |
| `ctrl+s` (Settings), `ctrl+,` | open or close settings |
| `tab` (Switch search / ask), `shift+tab` | switch between searching and asking without changing Vim mode |
| `esc` | leave one step: cancel a pending/active find, normal mode from insert, the field from a list, the panel from the field |

## The field

Insert mode:

| key | does |
|---|---|
| `jk` (the escape sequence) | to normal mode |
| `ctrl+w` | delete the word before the cursor |
| `ctrl+u` | delete to the start of the line |
| `ctrl+j` | a line break in a question — AI mode; the bar grows a row, up to six |
| `ctrl+c` `ctrl+n` `ctrl+x` | AI mode: a new conversation, the next saved one, forget this one |
| `ctrl+shift+x` | AI mode: forget every saved conversation (twice) |
| `down` `up` | a line down or up within a question of several lines; down from the last, into the results or the transcript |
| `enter` (Search / ask) | search and focus the first result when it arrives; asking leaves the field in normal mode |

Normal mode uses vim editing: `h l w W b B e 0 ^ $`, `f F t T{char}`;
after a find, `f`/`F` keep walking that character forward/backward, and `;`/`,`
also repeat/reverse. All matches on the line are highlighted; the current one
uses the accent colour. `i a I A`, `o O` (open a line below/above in AI mode), `r{char}`, `x`, `d c y` with a motion or doubled (`dd cc yy`), `v`,
counts (`3w`, `2dw`), and text objects (`diw`, `ci"`, `da(`). `p` `P` put
the system clipboard after or before the cursor — every yank in the panel,
field or answer, lands there — and in visual mode replace the selection.
`Shift+V` (`V`) selects whole lines in normal mode. `j`/`k` and up/down
extend the selection; counts work (`2j`). `y` copies, `d` deletes, and `c`
changes the selected lines. `Esc` or `V` leaves line selection.

`yy` copies the current line, `dd` deletes it and keeps the cursor column on
the line that replaces it (clamped when shorter), and `cc` changes it; counts
operate on consecutive lines (`2yy`, `2dd`). In multiline questions, other
text motions retain their existing behavior. `j` or `down` steps into what is below. Deliberately absent: `.` repeat, macros, marks,
named registers.

## The results

Settings → Display → Line numbers selects `relative` (default), `absolute`, or
`hide` for both panes. Relative numbers show distance from the cursor (0 on the
current row); absolute result numbers start at 1 on each page. Counts move
relative to the current row: `2j` moves down two results, `2k` moves up two.

| key | does |
|---|---|
| `j` `k`, `down` `up` | move the cursor; a count repeats the move (`2j`, `10k`) |
| `ctrl+d` `ctrl+u` | half a screen |
| `gg` `G` | first, last |
| `l` (Next page), `right` | next page |
| `h` (Previous page), `left` | previous page |
| `enter` (Open) | open in the browser and dismiss |
| `ga` (Hand off to agent) | the selected result's URL on its own, as an editable draft in the agent |
| `gA` (Hand off everything) | every URL on the current page, one per line, as an editable draft |
| `gi` (Back to the field) | back to the field, normal mode |
| `/` | back to the field, normal mode |
| `i` | back to the field, insert before the cursor, as in vim |
| `a` | back to the field, insert after the cursor, as in vim |
| `esc` | back to the field, normal mode |

## The answer

The gutter follows the Line numbers setting, counting displayed lines including
wrapped lines. Absolute numbers start at 1 across the transcript. `2j` moves down two displayed lines; `2k` moves up two. Numbers
follow the layout when the panel width changes and are excluded from copied text.

| key | does |
|---|---|
| `j` `k` `h` `l`, arrows | move the cursor by line and character |
| `w` `W` `b` `B` `e` `E` | by word |
| `0` `^` `home`, `$` `end` | line ends |
| `f` `F` `t` `T` {char}, `;` `,` | find on the line; matches are highlighted with the current one accented, and `f`/`F` keep walking forward/backward |
| `gg` `G` | transcript ends |
| `ctrl+d` `ctrl+u` | half a screen |
| a count | repeats a motion: `3w`, `2j`, `2fx` |
| `v` | select by character |
| `Shift+V` (`V`) | select by displayed line; `j`/`k` extend and `y` copies (response stays read-only) |
| `iw` `aw` `i"` `a(` … in visual mode | select a text object on the line: `viw`, `vi"` |
| `gv` | reselect what was last selected |
| `y` {motion} | yank: `yw`, `ye`, `y$`, `yfx`, `2yw`; `yj` `ygg` take whole lines |
| `yiw` `ya(` … | yank a text object |
| `y` in visual mode | yank the selection |
| `yy` | yank the current displayed line; `2yy` yanks two displayed lines |
| `p` `P` | put into the ask bar and go there: the selection in visual mode, else the clipboard (so `yiw` then `p`) |
| `gx` (Open link) | open the link under the cursor — a Markdown link, a bare URL, or a bare domain such as `rust-lang.org` — or, in visual mode, the selected URL; http and https only, a bare domain gets `https://` |
| `enter` (Open) | open the link under the cursor or in the selection |
| `ga` (Hand off to agent) | the selection; else the reply under the cursor and the question it answers, as the agent wrote them — an editable draft |
| `gA` (Hand off everything) | the whole conversation, failures left out, as an editable draft |
| `ctrl+c` (New session) | start a new conversation, keeping this one in the ring |
| `ctrl+n` (Next session) | the next saved conversation, wrapping |
| `ctrl+x` (Close session) | forget this conversation and show the one below it |
| `ctrl+shift+x` (Delete all sessions) | forget every saved conversation, on a second press |
| `gi` (Back to the field) | back to the field, normal mode |
| `/` | back to the field, normal mode |
| `i` | back to the field, insert before the cursor, as in vim |
| `a` | back to the field, insert after the cursor, as in vim |
| `esc` | drop the selection or active find, else back to the field |

## Settings

| key | does |
|---|---|
| `j` `k` | move between rows, stepping over section headings and the fixed-key list |
| `h` `l` | change the value under the cursor; on the SearXNG switch, off and on |
| `enter`, `i` | open a typed row for editing, flip the SearXNG switch, or open a dropdown |
| `gg` `G` | first, last row |
| `enter` while editing | commit — a refused key says why under its label until the cursor moves |
| `esc` while editing | cancel |
| `j` `k`, `enter`, `esc` in an open dropdown | walk it, pick, close |
| `/` | back to the field, normal mode |
| `esc`, `ctrl+s` (Settings), `ctrl+,` | back to the panel |

The settings page scrolls within the panel; keyboard navigation keeps the
selected row visible. Values are written as they change; there is no save.

## The setup prompt

| key | does |
|---|---|
| `h` `l`, arrows, `tab` | choose |
| `enter` | confirm |
| `esc` | not now |

## Where they live in the source

- `src/lib/keybinds.mjs` — `ACTIONS`, every rebindable key with its default, scope and label; binding text ↔ chord strings (`"ctrl+c"` ↔ `"C-c"`, `"gx"` ↔ `"g x"`)
- `src/lib/keys.mjs` — the fixed keys of the two panes that are *read* (results, answer); `readerKeys` merges in the rebound ones, chord → command name; `bindingProblem` is the clash check the settings page runs
- `src/lib/settings.mjs` — the Keys rows (one per action) and the Fixed keys rows (`FIXED_KEYS`)
- `src/components/chord.js` — Qt key events → chord strings
- `src/components/VimTextField.qml` — the field's mode machine and everything vim
- `src/components/ResultList.qml`, `AnswerView.qml`, `SettingsPage.qml`, `SetupPrompt.qml` — each view's own dispatch
- `src/lib/sessions.mjs` — the ring of saved conversations the session keys walk
