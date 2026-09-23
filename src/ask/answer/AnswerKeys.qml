import QtQuick
import "../../shared/vim/chord.js" as Chord
import "../../shared/vim/grammar.mjs" as Grammar
import "../../shared/vim/keys.mjs" as KeysLib
import "../../shared/vim/motions.mjs" as Motions

// The answer's keys: a press through the grammar (counts, y, the key after f
// or i/a) into an action, then the action done — a motion taken with or
// without the y waiting on it, a find, a text object, or a command, which
// is either the view's own or a signal for the panel.
Item {
  id: keys

  property var view: null

  function press (event) {
    view.following = false        // the reader is reading; stop dragging them to the newest line
    // An open prompt takes every key into the pattern before the grammar sees one.
    if (view.finder.feed(event)) {
      event.accepted = true
      return
    }
    const chord = Chord.of(event)
    // ctrl+shift+c copies the selection, else the reply under the cursor, as y does.
    const clipboard = KeysLib.clipboardCommand(chord)
    if (clipboard !== "") {
      view.grammar = Grammar.IDLE
      run(clipboard, 1)
      event.accepted = true
      return
    }
    if (chord !== "" && chord === view.chords.newSession) {
      view.grammar = Grammar.IDLE
      view.newSessionRequested()
      event.accepted = true
      return
    }
    const step = Grammar.feed(view.grammar, chord, view.readerKeys, view.selecting, view.repeatFindReady ? view.lastFind : null)
    view.grammar = step.state
    if (!step.action && chord !== "") {
      const onlyCount = view.grammar.count > 0 && view.grammar.keys === "" && view.grammar.before === 0 &&
        view.grammar.operator === "" && view.grammar.find === "" && view.grammar.scope === ""
      if (!onlyCount) view.repeatFindReady = false
    }
    perform(step.action)
    event.accepted = true
  }

  function perform (action) {
    if (!action) return
    if (action.type !== "find" && action.type !== "repeatFind") view.repeatFindReady = false
    switch (action.type) {
    case "command": {
      // k on the first line: nothing above it but the field, so k goes up to
      // the field, as j from the field came down. Not mid-selection or mid-y.
      if (action.command === "up" && !action.operator && !view.selecting && view.mover.lineFrom(view.cursor, -1, 0) === -1) {
        view.normalRequested()
        break
      }
      const target = view.mover.motionTarget(action.command, action.count, action.operator)
      if (target) view.mover.go(target, action.operator)
      else if (!action.operator) run(action.command, action.count)   // y then a non-motion: dropped, as vim does
      break
    }
    case "find":
      {
        const target = view.mover.findTarget(action.command, action.char, action.count, false)
        if (target.pos >= 0) {
          view.lastFind = { command: action.command, char: action.char }
          view.repeatFindReady = true
          view.currentFindHit = Motions.findMatchPosition(target.pos, action.command)
        }
        view.mover.go(target, action.operator)
      }
      break
    case "repeatFind":
      if (!view.lastFind) break
      {
        const command = action.command || (action.reverse ? Motions.flipFind(view.lastFind.command) : view.lastFind.command)
        const target = view.mover.findTarget(command, view.lastFind.char, action.count, true)
        if (target.pos >= 0) {
          if (action.command) view.lastFind = { command: command, char: view.lastFind.char }
          view.repeatFindReady = true
          view.currentFindHit = Motions.findMatchPosition(target.pos, command)
        }
        view.mover.go(target, action.operator)
      }
      break
    case "object": view.selector.takeObject(action.scope, action.object, action.operator); break
    case "line":   view.selector.yankLines(action.count); break
    }
  }

  function run (command, count) {
    const times = count === undefined ? 1 : Math.max(1, count)
    switch (command) {
    case "settings":     view.settingsRequested(); break
    case "keysHelp":     view.keysRequested(); break
    case "toggleMode":   view.tabbed(); break
    case "switchAgent":  view.agentSwitchRequested(); break
    // L / H walk the ring, as h and l page the results; ctrl+n lands here too.
    case "nextSession":  view.sessionWalked(times); break
    case "previousSession": view.sessionWalked(-times); break
    case "closeSession": view.closeSessionRequested(); break
    case "paneRight":    view.paneRightRequested(); break
    case "paneLeft":     view.paneLeftRequested(); break
    case "clearSessions": view.clearSessionsRequested(); break
    case "stopAnswer":   view.stopRequested(); break
    case "retryAnswer":  view.retryRequested(); break
    case "handOff":      view.actions.handOff(); break
    case "handOffPage":  view.actions.handOffAll(); break
    case "accept":       view.actions.openLink(); break
    // Esc leaves one step at a time, and a search is one of them: drop the
    // selection, then the search and its highlight, and only then the pane.
    case "cancel":
      if (view.selecting) view.selector.stopSelecting()
      else if (view.finder.lastPattern) view.finder.forget()
      else view.escaped()
      break
    case "fieldNormal":  if (view.selecting) view.selector.stopSelecting(); view.normalRequested(); break
    case "insert":       view.insertRequested(); break
    case "append":       view.appendRequested(); break
    case "selectChars": if (view.selecting && !view.linewise) view.selector.stopSelecting(); else view.selector.startSelecting(false); break
    case "selectLines": if (view.selecting && view.linewise) view.selector.stopSelecting(); else view.selector.startSelecting(true); break
    case "reselect":    view.selector.reselect(); break
    case "yank":
    case "copy":        view.selector.yank(); break
    case "paste":       if (view.selecting) view.selector.stopSelecting(); view.pasteRequested(); break
    case "openLink":    view.actions.openLink(); break
    case "searchFor":   view.actions.searchFor(); break
    case "translate":   view.actions.translate(); break
    case "askAbout":    view.actions.askAbout(); break
    case "askNow":      view.actions.askNow(); break
    case "put":         view.actions.put(true); break
    case "putBefore":   view.actions.put(false); break
    case "findForward":  view.finder.open(false, view.cursor); break
    case "findBackward": view.finder.open(true, view.cursor); break
    case "searchWord":     view.searchWordUnderCursor(false); break
    case "searchWordBack": view.searchWordUnderCursor(true); break
    }
  }
}
