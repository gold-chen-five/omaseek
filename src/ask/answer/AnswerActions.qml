import QtQuick
import "../transcript.mjs" as Transcript
import "../../shared/urls.mjs" as Urls
import "../../shared/vim/textobjects.mjs" as TextObjects

// What the answer hands to the rest of the panel: text into the ask bar (p,
// gf), a question asked (gd), a search (gs), a translation (gt), a link to open (gx), or the reply and
// its question to the agent (ga, gA). Each takes the selection when there is
// one, drops it, and raises the view's signal.
Item {
  id: actions

  property var view: null

  // p and P hand text to the ask bar, where it can be edited: the selection
  // in visual mode, else "" and the field reads the clipboard, where every
  // yank here lands.
  function put (after) {
    const value = view.selector.selection()
    if (view.selecting) view.selector.stopSelecting()
    view.putRequested(value, after)
  }

  // gf and gd: the selection, else the displayed line under the cursor — the
  // same unit yy takes. gf puts it in the ask bar to type a question about; gd
  // asks about it straight away.
  function askAbout () {
    const text = passage()
    if (text.trim()) view.askRequested(text)
  }

  function askNow () {
    const text = passage()
    if (text.trim()) view.askNowRequested(text)
  }

  function passage () {
    if (view.selecting) {
      const text = view.selector.selection()
      view.selector.stopSelecting()
      return text
    }
    const from = view.mover.lineStartAt(view.cursor)
    const next = view.mover.lineFrom(view.cursor, 1, 0)
    const to = next < 0 ? view.answer.length : view.mover.lineStartAt(next)
    return Transcript.cut(view.plain().substring(from, to), from, view.selector.leadRanges())
  }

  // gs: the selection, else the word under the cursor, the way vim's * takes one.
  // A selection is already a whole query, so Search.qml runs it rather than
  // leaving it in the field.
  function searchFor () {
    const text = (view.selecting ? view.selector.selection() : wordUnderCursor()).trim()
    if (view.selecting) view.selector.stopSelecting()
    if (text) view.searchRequested(text)
  }

  // gt: the selection, else the word under the cursor — what gs would search.
  function translate () {
    const text = (view.selecting ? view.selector.selection() : wordUnderCursor()).trim()
    if (view.selecting) view.selector.stopSelecting()
    if (text) view.translateRequested(text)
  }

  function wordUnderCursor () {
    const source = view.plain()
    const range = TextObjects.resolveInLine(source, view.cursor, "i", "w")
    return range ? source.substring(range.start, range.end) : ""
  }

  function openLink () {
    const url = view.selecting ? Urls.urlFromSelection(view.selector.selection()) : view.linkUnder(view.cursor)
    if (!url) return
    if (view.selecting) view.selector.stopSelecting()
    view.linkOpened(url)
  }

  // The selection; else the reply under the cursor and the question it
  // answers, as the agent wrote it, so its Markdown links survive the draft.
  function handOff () {
    if (view.selecting) {
      const context = view.selector.selection()
      view.selector.stopSelecting()
      view.handedOff(context)
      return
    }
    if (view.plainDocument) {
      view.handedOff(view.document)
      return
    }
    const r = Transcript.replyIndexAt(view.cursor, view.questionStarts, view.replyStarts)
    view.handedOff(r === -1 ? Transcript.conversationText(view.turns) : Transcript.exchangeText(view.turns, view.replyTurns[r]))
  }

  function handOffAll () {
    if (view.selecting) view.selector.stopSelecting()
    view.handedOff(view.plainDocument ? view.document : Transcript.conversationText(view.turns))
  }
}
