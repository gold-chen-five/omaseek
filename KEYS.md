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
| Translate the bar (any mode) | `translate_bar_anywhere_key` | `ctrl+t` | field, insert mode too: everything in the search or ask bar |
| Translate the bar | `translate_bar_key` | `gT` | field, normal mode: everything in the search or ask bar |
| Translate | `translate_key` | `gt` | answer: the selection, or the word under the cursor · field: the selection, in visual mode |
| Previous query / question | `previous_asked_key` | `U` | field, normal mode: what you searched or asked before, one step back each press (`up` on the first line too) |
| New session | `new_session_key` | `ctrl+c` | field and answer: forget the conversation and start one |
| Next session | `next_session_key` | `ctrl+n` | ask: the next saved conversation, newest first, wrapping |
| Next conversation | `next_chat_key` | `L` | ask: the next saved conversation, wrapping (`3L` walks three) |
| Previous conversation | `previous_chat_key` | `H` | ask: the conversation before, wrapping |
| Close session | `close_session_key` | `ctrl+x` | closes what the keyboard is in: in ask, this conversation (showing the one below it); in the translation, that |
| Delete all sessions | `clear_sessions_key` | `ctrl+shift+x` | ask: forget every saved conversation, on the second press |
| Retry answer | `retry_answer_key` | `ctrl+shift+r` | ask: ask the last question again after a failure, a stop, or an interruption |
| Settings | `settings_key` | `ctrl+s` | anywhere: open or close settings (`ctrl+,` always works too) |
| Look up keys | `keys_help_key` | `ctrl+k` | anywhere, insert mode too: every key in the panel, as bound now, in a list you type into to filter |
| Switch search / ask | `switch_mode_key` | `tab` | anywhere, without changing Vim mode |
| Switch agent | `switch_agent_key` | `shift+tab` | anywhere: the next installed agent answers from now on, wrapping; the conversation so far goes with it |
| Open | `open_key` | `enter` | results: open the result and dismiss · answer: the link under the cursor or in the selection |
| Hand off to agent | `handoff_key` | `ga` | results: the selected result's URL, alone · answer: the selection, else the reply under the cursor with its question · field: the bar, or the selection |
| Hand off everything | `handoff_all_key` | `gA` | results: every URL on the page · answer: the whole conversation · field: that, with the bar's text under it |
| Ask about this | `ask_now_key` | `gd` | results: the selected result's title and URL · answer and translation: the selection, or the line under the cursor — asked straight away, and you land in the answer |
| Put in the ask bar | `ask_about_key` | `gj` | results: the selected URL over in the ask bar · answer and translation: the selection, or the line under the cursor — unsent |
| Search for this | `search_for_key` | `gs` | results: search for the selected result's title · answer: search the web for the selection, or the word under the cursor |
| Open link | `open_link_key` | `gx` | answer: the URL under the cursor or in the selection |
| Next page | `next_page_key` | `l` | results (`right` always works too) |
| Previous page | `previous_page_key` | `h` | results (`left` always works too) |
| Back to the field | `insert_key` | `gi` | results and answer: return to the field, insert mode (`i` and `a` do too) |
| Back to the field (normal) | `normal_key` | `gn` | results and answer: return to the field in normal mode (`esc` does too) |

A hand-off opens the agent (Settings → Ask → Hand off to) with the text
pasted into its input and not sent: edit it, then submit it yourself.

`gd`, `gj` and `gs` stay inside the panel instead. `gd` asks the AI about
something straight away — from the results, the result's title and URL; from an
answer or a translation, the selection or the line under the cursor — and moves
you into the answer, as Enter in the ask bar does; a draft half-typed there is
left alone. `gj` puts the same thing in the ask bar and leaves it there, unsent,
so a question can be typed beneath it. `gs` goes the other way and *does* run: the
words you selected are already a whole query. Either way `tab` returns to
the half you came from, with what was there still there.

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

A reply appears as the agent writes it, where its CLI can do that — Claude
Code can, and the rest answer whole, which is the same wait as before with
nothing lost. **Ctrl+S → Ask → Answer as it is written** turns it off. The words
on screen are only the reply so far: what is saved when the turn ends is the
answer the CLI itself settled on, so nothing that flickers past can end up in
the conversation.

**A question keeps being answered after you leave it.** `ctrl+c` while the agent
is thinking opens a new conversation and lets the old one finish: its square
keeps a pulsing dot until the reply lands, and the reply lands in *that*
conversation, so `ctrl+n` back to it shows the finished answer. You can ask in
the new conversation straight away — each question has its own agent process.
To stop an answer without leaving it, press `q` or `esc` in normal mode — in the
answer, or in the field (asking leaves it in insert, so there it is `esc` twice,
the first leaving insert). The words written so far
stay on screen under a `■ stopped` mark (or `⚠ Stopped before the agent
answered`), the conversation stays in the ring, and the agent process is ended.
`ctrl+shift+r` then asks the same question again, replacing the stopped reply —
and it does the same after a failure, or for a question whose answer a shell
restart lost. A stopped reply is never sent back to the agent as if it were an
answer. The `chat` button reads `stop` while a reply is coming and `retry`, with
an empty field, when there is one to retry. Retry is `ctrl+shift+r` because
`ctrl+r` is redo in the field.

`ctrl+x` is the one key that does cancel and forget: closing a conversation stops the
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
| `super+d` | summon or dismiss (Hyprland, not the panel — `omarchy-shell shell toggle omaseek`). Not bound on install: Settings → Keys → *Open omaseek with* → Add writes it, only while the key is free |
| `ctrl+s` (Settings), `ctrl+,` | open or close settings |
| `ctrl+k` (Look up keys) | every key in the panel as `key — what it does`, grouped by where it works and showing your current bindings. Type to filter — any words, in any case (`trans`, `ctrl+x`, `undo`); `↓` `↑`, `ctrl+n` `ctrl+p`, `ctrl+d` `ctrl+u` scroll; `esc` or `ctrl+k` closes it and the keyboard goes back where it was, in the mode it was in |
| `tab` (Switch search / ask) | switch between searching and asking without changing Vim mode |
| `shift+tab` (Switch agent) | the next installed agent answers from now on, wrapping — the status line says who. A conversation already under way goes with it: every question carries the turns before it (the last eight), whichever agent wrote them |
| `esc` | leave one step: close an open `/` prompt, drop a search and its highlight, cancel a pending/active find, drop a selection, normal mode from insert, the field from a list, the panel from the field |

## The field

The bar's cursor shows only while the field has the keyboard: once Enter
moves you into the answer or the results, the cursor is there alone.

Insert mode:

| key | does |
|---|---|
| `jk` (the escape sequence) | to normal mode |
| `ctrl+w` | delete the word before the cursor |
| `ctrl+u` | delete to the start of the line |
| `ctrl+j` | a line break in a question — AI mode; the bar grows a row, up to six |
| `ctrl+c` `ctrl+n` `ctrl+x` | AI mode: a new conversation, the next saved one, forget this one |
| `ctrl+shift+x` | AI mode: forget every saved conversation (twice) |
| `ctrl+shift+r` | AI mode: ask the last question again after a failure or a stop |
| `up` `down` | search: the field is one line, so they walk the queries searched before — `up` an older one, `down` back toward what you had typed, then into the results |
| `up` `down` | ask: a line up or down within a question of several lines; past the first line, `up` walks the questions asked before, and past the last, `down` comes back toward what you had typed, then into the transcript |
| `gT` (Translate the bar) | normal mode: translate everything in the bar — search or ask — into the panel on the right |
| `ctrl+t` (Translate the bar, any mode) | the same from insert mode, without leaving it: type, press it, keep typing |
| `gt` (Translate) | visual mode: translate the selection |
| `ga` (Hand off to agent) | normal mode: everything in the bar, as an editable draft in the agent; visual mode: the selection |
| `gA` (Hand off everything) | normal mode: what `gA` below would hand off — the page's URLs in search, the conversation in ask — with the bar's text under it |
| `gd` (Ask about this) | the bar, or the selection, asked straight away — as Enter in the ask bar, from search too; you land in the answer |
| `gj` (Put in the ask bar) | the selection, or a search moved over, into the ask bar unsent |
| `gs` (Search for this) | the bar, or the selection, searched — as Enter in search, from ask too |
| `U` (Previous query / question) | normal mode: one step back through what was searched or asked before, as `up` is — in either half, a count stepping further (`3U`) |
| `enter` (Search / ask) | search and focus the first result when it arrives — or, when the field holds an address, open it in the browser; asking moves you into the answer |

`gx` in normal mode opens the URL or bare domain under the cursor in the browser,
as vim's does; in visual mode, the selected one.

**Paste an address to go there.** In search mode, Enter on a field that holds
only an address opens it instead of searching, and the status line says so
first (`enter opens rust-lang.org`). An address is an `http(s)://` URL, a
`www.` one, a common web domain (`rust-lang.org`, `socket.io`), any domain with
a path or port (`docs.rs/tokio`), or `localhost` / an IP with a port. Anything
that could be a file or a version — `vue.js`, `README.md`, `main.rs`,
`python3.12` — is still searched. `gs` on a result always searches, even for
a title that looks like a domain.

In AI mode, Enter asks and moves you into the answer, where the reply is
written as you watch; `i`, `a` or `gi` go back to the field for the next
question. While a reply is being written, `q` in the answer stops it — and in
the field, `q` or `esc` in normal mode (`esc` closes the panel again once
nothing is being written); `q` otherwise does nothing, since macros are absent.

Normal mode uses vim editing: `h l w W b B e 0 ^ _ $` (on the line under the cursor, in a question of several), `gg` `G` (the first and last line of a question — `3G` or `3gg` the third, `dG` `ygg` whole lines), `f F t T{char}`;
after a find, `f`/`F` keep walking that character forward/backward, and `;`/`,`
also repeat/reverse. All matches on the line are highlighted; the current one
uses the accent colour. `i a I A`, `o O` (open a line below/above in AI mode), `r{char}`, `x`, `d c y` with a motion or doubled (`dd cc yy`), `v`,
counts (`3w`, `2dw`), and text objects (`diw`, `ci"`, `da(`). `u` undoes and
`ctrl+r` redoes a whole change at a time, as vim does: `ciw`, the word typed and
the `jk` that left insert are one `u`, and a count undoes several (`3u`). `p` `P` put
the system clipboard after or before the cursor — every yank in the panel,
field or answer, lands there — and in visual mode replace the selection.
`Shift+V` (`V`) selects whole lines in normal mode. `j`/`k` and up/down
extend the selection; counts work (`2j`). `y` copies, `d` deletes, and `c`
changes the selected lines. `Esc` or `V` leaves line selection.

The last twenty-five queries are kept in
`~/.local/share/omaseek/queries.json` and survive a shell restart. Searching the
same thing again moves it to the front rather than repeating it. The walk does
not wrap: past the oldest it stops, and coming back the other way it puts back
the query you were halfway through typing. `j` and `k` never walk it — `j` into
the results is how you reach them.

`yy` copies the current line, `dd` deletes it and keeps the cursor column on
the line that replaces it (clamped when shorter), and `cc` changes it; counts
operate on consecutive lines (`2yy`, `2dd`). In multiline questions, other
text motions retain their existing behavior. `j` or `down` steps into what is below — the results or the answer, or a translation when there is nothing else to read. Deliberately absent: `.` repeat, macros, marks,
named registers.

## The results

Settings → Display → Line numbers selects `relative` (default), `absolute`, or
`hide` for both panes. Relative numbers show distance from the cursor (0 on the
current row); absolute result numbers start at 1 on each page. Counts move
relative to the current row: `2j` moves down two results, `2k` moves up two.

The row under the cursor is lit only while the results have the keyboard, so
typing in the field never looks like it would act on a row.

| key | does |
|---|---|
| `j` `k`, `down` `up` | move the cursor; a count repeats the move (`2j`, `10k`) |
| `ctrl+d` `ctrl+u` | half a screen |
| `gg` `G` | first, last |
| `l` (Next page), `right` | next page; after `page failed` on the status line, it retries that page. A count walks several: `5l` is five pages on |
| `h` (Previous page), `left` | previous page; `3h` three back, never past the first |
| `5gp` | jump to page 5; `gp` alone is page 1. Cached pages are instant, the rest are fetched one by one and the status line counts them (`page 4 of 7 · loading…`). A jump asks for at most ten new pages, so `500gp` goes ten on and another `gp` carries on |
| `enter` (Open) | open in the browser and dismiss |
| `ga` (Hand off to agent) | the selected result's URL on its own, as an editable draft in the agent |
| `gA` (Hand off everything) | every URL on the current page, one per line, as an editable draft |
| `y` | copy the selected result's URL |
| `Y` | copy its title and URL, on two lines |
| `gd` (Ask about this) | ask the AI about the selected result — its title and URL — straight away |
| `gj` (Put in the ask bar) | the selected URL over in the ask bar, to type a question around — it is not sent |
| `gs` (Search for this) | search for the selected result's title |
| `ctrl+l` | into the translation beside the results, while one is open |
| `ctrl+x` (Close session) | close the translation beside the results — there is no conversation here to forget |
| `/` `?` | search the rows — title, snippet and domain — forwards or backwards; the matched words are marked |
| `n` `N` | the next match and the one before; a count repeats (`3n`) |
| `esc` after a search | drop it and its marks, staying on the results |
| the numbered squares | under the status line, one square a page and a `›` for the page not fetched yet: the mouse's `h`, `l` and `5gp`. Past ten pages the row is a window around the one being read. **Ctrl+S → Display → Page numbers** decides what they say: `absolute` (the default) gives each square its own page number; `relative` counts from the page on screen (`2 1 0 1 2`), so `3h` and `5l` read straight off the row |
| `gi` (Back to the field) | back to the field, insert mode |
| `gn` (Back to the field (normal)) | back to the field, normal mode |
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
| `0` `^` `_` `home`, `$` `end` | line ends |
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
| `gs` (Search for this) | search the web for the selection, or the word under the cursor — a selection is already a whole query, so this one runs |
| `gx` (Open link) | open the link under the cursor — a Markdown link, a bare URL, or a bare domain such as `rust-lang.org` — or, in visual mode, the selected URL; http and https only, a bare domain gets `https://` |
| `enter` (Open) | open the link under the cursor or in the selection |
| `ga` (Hand off to agent) | the selection; else the reply under the cursor and the question it answers, as the agent wrote them — an editable draft |
| `gA` (Hand off everything) | the whole conversation, failures left out, as an editable draft |
| `gt` (Translate) | the selection, or the word under the cursor, translated into the panel on the right |
| `gd` (Ask about this) | ask the AI about the selection — or the line under the cursor — straight away |
| `gj` (Put in the ask bar) | the selection — or the line under the cursor — into the ask bar as written, with the cursor under it to type a follow-up. Not sent |
| `ctrl+c` (New session) | start a new conversation, keeping this one in the ring |
| `ctrl+n` (Next session) | the next saved conversation, wrapping |
| `L` `H` (Next/Previous conversation) | the next saved conversation and the one before, wrapping — where search pages with `h` and `l`. Read in the answer and in the field's normal mode. A count walks several (`3L`), and the numbered squares below do the same with a click |
| `ctrl+l` | into the translation beside the answer, while one is open |
| `ctrl+x` (Close session) | forget this conversation and show the one below it — even with a translation open; `ctrl+l` there and `ctrl+x` closes that instead |
| `ctrl+shift+x` (Delete all sessions) | forget every saved conversation, on a second press |
| `q` | stop the reply being written, keeping what arrived |
| `ctrl+shift+r` (Retry answer) | ask the last question again after a failure or a stop |
| `/` `?` | search the transcript forwards or backwards |
| `*` `#` | search for the word under the cursor, forwards or backwards — whole words only |
| `n` `N` | the next match and the one before — a motion, so counts and yanks work: `3n`, `y2n` |
| `gi` (Back to the field) | back to the field, insert mode |
| `gn` (Back to the field (normal)) | back to the field, normal mode |
| `i` | back to the field, insert before the cursor, as in vim |
| `a` | back to the field, insert after the cursor, as in vim |
| `esc` | drop the selection, then the search and its highlight, then back to the field |

### Searching a pane

`*` searches for the word under the cursor without a prompt, and `#` searches
back for it. On a space they take the next word on the line, as vim's do. They
match whole words only — `*` on `rust` passes over `rusty` and `trust`, which is
the whole difference between it and typing the word after `/`. Otherwise they
leave exactly what an accepted prompt leaves, so the matches stay lit and `n`
and `N` carry on from there.

`/` opens a prompt on the status line and `?` searches backwards. What you type
lands there, not in the search field — every key goes into the pattern until
`enter` accepts it or `esc` drops it, and `backspace` past the start closes the
prompt, as vim's does. While you type, the cursor follows the first match from
where you were; `esc` puts it back where it started.

In the answer, matches are lit the way `f` and `t` light theirs, the one under
the cursor accented. The results have no layout to light behind, so there the
matched words are marked in the text itself — bold, and in the accent on every
row but the one the cursor is on, which is painted in the accent already. A lowercase pattern matches either case and one uppercase letter
anywhere pins it — vim's smartcase. `n` and `N` walk the matches and wrap, `N`
reversing whichever direction the search was made in.

`esc` leaves a search one step at a time, the way it leaves everything else
here: it closes an open prompt, or drops a finished search and its highlight
**without leaving the pane** — you stay on the result or the line you had
walked to. Only once there is no search left does another `esc` return you to
the field. Leaving the pane by any other route forgets the search too.

`/` used to mean "back to the field". It does not any more: `gi` goes back
typing, `gn` goes back in normal mode, and `i`, `a` and `esc` still go back too.
The settings page keeps `/` for going back, since there is nothing there to
search.

## Settings

| key | does |
|---|---|
| `j` `k` | move between rows, stepping over section headings and the fixed-key list |
| `h` `l` | change the value under the cursor; on a switch (SearXNG, each engine), off and on |
| `enter`, `i` | open a typed row for editing, flip a switch, press a button (Update, Test), or open a dropdown |
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

- `src/shared/vim/keybinds.mjs` — `ACTIONS`, every rebindable key with its default, scope and label; binding text ↔ chord strings (`"ctrl+c"` ↔ `"C-c"`, `"gx"` ↔ `"g x"`)
- `src/shared/vim/keys.mjs` — the fixed keys of the two panes that are *read* (results, answer); `readerKeys` merges in the rebound ones, chord → command name; `bindingProblem` is the clash check the settings page runs
- `src/settings/rows.mjs` — the Keys rows (one per action); `src/settings/choices.mjs` — the Fixed keys rows (`FIXED_KEYS`)
- `src/shared/vim/chord.js` — Qt key events → chord strings
- `src/field/` — the field: `VimTextField.qml` routes each key to `FieldPanelKeys` (the panel's keys, every mode), `FieldInsert` (insert mode and `jk`), `FieldNormal` (normal and visual), `FieldPending` (the key after `f`/`t`, `r`, `i`/`a`, `g`), `FieldEdits` (what they do to the text) and `FieldUndo` (`u` and `ctrl+r`, a step per change — the rules are `src/shared/vim/undo.mjs`)
- `src/ask/answer/AnswerKeys.qml` — the answer's dispatch; `src/search/ResultList.qml`, `src/settings/SettingsPage.qml`, `src/engine/SetupPrompt.qml` — each view's own
- `src/panel/Commands.qml`, `src/ask/ChatCommands.qml` — what a key asks the panel to do
- `src/ask/sessions.mjs` — the ring of saved conversations the session keys walk

## Translate

`gt` on a selection — in an answer, or in the field's visual mode — `gT` on the
whole bar (`ctrl+t` from insert mode), or the **translate** button beside search and chat, translates into
the panel split off to the right of the results or the answer. The keyboard
stays where it was; `ctrl+l` moves it into the translation — the header and the
seam light up while it has it — and `ctrl+h` moves it back. A new translation
replaces the one showing.

`ctrl+x` closes what the keyboard is in, so in ask mode it forgets the
conversation from the answer or the field and closes the translation only from
inside it. Search has no conversation to forget, so there `ctrl+x` from the
field or the results closes the translation too.

In the translation, every key of [the answer](#the-answer) works, since it is
read with the same view: `h j k l w b e 0 ^ $ gg G`, `f t ; ,`, counts, `v V`,
`y{motion}` `yy` `yiw`, `/ ? n N * #`, `p P` into the ask bar, `gd` `gj` `gs` `gx`,
`ga` `gA` (the selection, or the whole translation), and `gt` to translate a
word of it again. Only `q` is missing — nothing is being written there. Beyond
those:

| key | does |
|---|---|
| `ctrl+x` (Close session) | close the translation; the keyboard goes back to the pane beside it, or the field when that is empty |
| `ctrl+h`, `esc` | back to the results or the answer (`esc` drops a selection or a search first) |
| `gi` `i` `a`, `gn` | back to the field, insert or normal mode |
| `×`, `copy` | the panel's buttons: close it, or copy the translation |

**Settings → Translate** chooses the language (**Translate into**, which by
default follows Search → Language / region and falls back to 繁體中文 — text
already in that language goes into English), and the agent and model that
translate, apart from Ask's so a quick model can do it. Translations are
`bin/ask --translate`: one question, no conversation, no web search.
