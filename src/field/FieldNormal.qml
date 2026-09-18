import QtQuick
import "../vim/motions.mjs" as Motions

// Normal and visual mode: a press sorted into what it is — esc, redo, an
// arrow, the key a pending f/r/i/g waits for, a count — and then vim's own
// commands, motions and operators, each done with FieldEdits.
Item {
  id: normalKeys

  property var field: null

  function press (event) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    if (event.key === Qt.Key_Escape) {
      if (field.mode === "visual") field.setMode("normal")
      else if (field.pendingOperator || field.pendingCount > 0 || field.pendingFind || field.repeatFindReady || field.pendingReplace > 0 || field.pendingTextObject || field.pendingG) field.clearPending()
      // While a reply is being written, esc stops it rather than closing the
      // panel; the one after that closes it.
      else if (field.stoppable) field.stopRequested()
      else field.cancelled()
      event.accepted = true
      return
    }

    if (ctrl && event.key === Qt.Key_R) {
      field.redo()
      field.clampCursor()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      field.edits.moveLine(event.key === Qt.Key_Down, true)
      event.accepted = true
      return
    }

    const key = event.text
    event.accepted = true
    if (!key || key.length !== 1) return

    if (field.pendingFind !== "") {
      field.pending.handlePendingFind(key)
      return
    }

    if (field.pendingReplace > 0) {
      field.pending.handleReplace(key)
      return
    }

    if (field.pendingTextObject !== "") {
      field.pending.handleTextObject(key)
      return
    }

    // After g: gx, and the translate keys (gt, gT) bound in settings.
    if (field.pendingG) {
      field.pendingG = false
      field.pendingCount = 0
      if (field.pendingOperator !== "") return
      const sequence = "g " + key
      // gt: the selection, from visual mode; gT: everything in the bar.
      if (sequence === field.normalChords.translate && field.mode === "visual") {
        const range = field.edits.visualRange()
        const selected = field.text.substring(range.start, range.end)
        field.setMode("normal")
        field.translateRequested(selected)
      } else if (sequence === field.normalChords.translateBar && field.mode !== "visual") {
        field.translateRequested(field.text)
      } else if (key === "x") {
        field.pending.openLinkUnderCursor()
      }
      return
    }
    if (key === "g" && field.pendingOperator === "") {
      field.pendingG = true
      return
    }

    // Vim's q records a macro, which this field deliberately lacks; here it
    // stops the reply being written, and otherwise does nothing.
    if (key === "q") {
      field.clearPending()
      if (field.stoppable) field.stopRequested()
      return
    }

    // 0 is a motion unless it is continuing a count.
    const isCountDigit = (key >= "1" && key <= "9") || (key === "0" && field.pendingCount > 0)
    if (isCountDigit) {
      field.pendingCount = field.pendingCount * 10 + parseInt(key, 10)
      return
    }

    handleNormalKey(key)
  }

  function handleNormalKey (key) {
    const count = field.takeCount(1)
    // The conversation keys, as the answer reads them: only ask mode has a ring,
    // so the panel ignores these while it is searching. Vim's H and L jump to
    // the top and bottom of the screen, which one line has no use for.
    if (key === field.normalChords.nextChat) { field.sessionWalked(count); return }
    if (key === field.normalChords.previousChat) { field.sessionWalked(-count); return }
    // U: one step back through what was searched or asked, as ↑ is on the
    // first line. Vim's U undoes a whole line, which u already covers here.
    if (key === field.normalChords.previousAsked) {
      for (let i = 0; i < count; i++) field.historyPrevRequested()
      return
    }
    const pos = field.mode === "visual" && field.visualLinewise ? field.visualCursor : field.cursorPosition
    const step = (motion, big) => Motions.repeat(at => motion(field.text, at, big), count, pos)
    if ("fFtT;,".indexOf(key) === -1) field.repeatFindReady = false

    switch (key) {
    // leaving the field — the result list is the next line down
    case "j":
    case "k":
      if ((field.mode === "visual" && !field.visualLinewise) || field.pendingOperator !== "") {
        field.clearPending()                      // dj and friends mean nothing here
        return
      }
      for (let i = 0; i < count; i++) field.edits.moveLine(key === "j", false)
      return

    // modes
    case "i":
      if (field.pendingOperator !== "" || field.mode === "visual") { field.pendingTextObject = "i"; return }
      field.setMode("insert")
      return
    case "a":
      if (field.pendingOperator !== "" || field.mode === "visual") { field.pendingTextObject = "a"; return }
      field.cursorPosition = Math.min(field.text.length, pos + 1)
      field.setMode("insert")
      return
    case "o": field.edits.openLine(true); return
    case "O": field.edits.openLine(false); return
    case "I": field.cursorPosition = Motions.firstNonBlank(field.text, pos); field.setMode("insert"); return
    case "A": field.cursorPosition = Motions.lineBounds(field.text, pos).end; field.setMode("insert"); return
    case "V":
      if (field.mode === "visual" && field.visualLinewise) {
        field.setMode("normal")
      } else {
        if (field.mode !== "visual") field.visualAnchor = pos
        field.visualLinewise = true
        field.mode = "visual"
        field.edits.applyMotion(pos, false)
      }
      return
    case "v":
      if (field.mode === "visual" && field.visualLinewise) {
        field.visualLinewise = false
        field.cursorPosition = pos
        field.select(field.visualAnchor, pos + 1)
      } else if (field.mode === "visual") {
        field.setMode("normal")
      } else {
        field.visualAnchor = pos
        field.mode = "visual"
        field.select(pos, pos + 1)
      }
      return

    // motions
    // Along the line and no further, as vim's h and l; an operator may take the
    // line to its end (3dl near the end deletes the rest of it).
    case "h": field.edits.applyMotion(Motions.charStep(field.text, pos, -count), false); return
    case "l": field.edits.applyMotion(Motions.charStep(field.text, pos, count, field.pendingOperator !== ""), false); return
    // A question can hold several lines; these keep to the one under the cursor.
    case "0": field.edits.applyMotion(Motions.lineBounds(field.text, pos).start, false); return
    case "^": field.edits.applyMotion(Motions.firstNonBlank(field.text, pos), false); return
    case "_":
      if (field.pendingOperator !== "") {           // d_ is dd, as in vim
        const operator = field.pendingOperator
        field.pendingOperator = ""
        field.edits.operateLines(operator, count * field.operatorCount)
        field.operatorCount = 1
        return
      }
      field.edits.applyMotion(Motions.firstNonBlank(field.text, Motions.linesDown(field.text, pos, count)), false)
      return
    case "$": field.edits.applyMotion(Motions.lineBounds(field.text, Motions.linesDown(field.text, pos, count)).end, false); return
    case "w": field.edits.applyMotion(step(Motions.wordForward, false), false); return
    case "W": field.edits.applyMotion(step(Motions.wordForward, true), false); return
    case "b": field.edits.applyMotion(step(Motions.wordBackward, false), false); return
    case "B": field.edits.applyMotion(step(Motions.wordBackward, true), false); return
    case "e": field.edits.applyMotion(step(Motions.wordEnd, false), true); return
    case "E": field.edits.applyMotion(step(Motions.wordEnd, true), true); return
    case "f": case "F": case "t": case "T":
      if (field.repeatFindReady && field.pending.sameFindKind(field.lastFindCommand, key)) {
        field.pending.repeatLastFind(key, count, true)
        return
      }
      field.pendingFind = key
      field.pendingCount = count > 1 ? count : 0
      field.repeatFindReady = false
      return
    case ";": case ",": {
      if (!field.lastFindCommand) return
      const command = key === "," ? Motions.flipFind(field.lastFindCommand) : field.lastFindCommand
      field.pending.repeatLastFind(command, count, false)
      return
    }

    // operators
    case "d": case "c": case "y":
      if (field.mode === "visual") {
        field.edits.operateOnVisual(key)
      } else if (field.pendingOperator === key) {   // dd / cc / yy act on the line
        field.pendingOperator = ""
        field.edits.operateLines(key, count * field.operatorCount)
        field.operatorCount = 1
      } else {
        field.pendingOperator = key
        field.operatorCount = count
      }
      return
    case "D": field.edits.applyOperator("d", pos, Motions.lineBounds(field.text, pos).end); return
    case "C": field.edits.applyOperator("c", pos, Motions.lineBounds(field.text, pos).end); return
    case "Y": field.edits.operateLines("y", count); return

    // single-key edits
    case "r":
      if (field.mode !== "visual") field.pendingReplace = count
      return
    case "x":
      if (field.mode === "visual") field.edits.operateOnVisual("d")
      else field.edits.applyOperator("d", pos, Math.min(field.text.length, pos + count))
      return
    case "X": field.edits.applyOperator("d", Math.max(0, pos - count), pos); return
    case "s": field.edits.applyOperator("c", pos, Math.min(field.text.length, pos + count)); return
    case "S":
      field.register = field.text
      field.edits.copyToClipboard(field.register)
      field.clear()
      field.setMode("insert")
      return
    case "p": case "P":
      if (field.mode === "visual") {                // the selection is replaced
        const range = field.edits.visualRange()
        const start = range.start
        const end = range.end
        field.setMode("normal")
        field.remove(start, end)
        field.cursorPosition = start
        field.edits.put(false, "")
      } else {
        field.edits.put(key === "p", "")
      }
      return
    case "u": field.undo(); field.clampCursor(); return
    }
  }
}
