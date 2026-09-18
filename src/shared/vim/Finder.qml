import QtQuick
import "find.mjs" as Find
import "chord.js" as Chord

// The `/` prompt, shared by the two panes that are read. They differ only in
// what a pattern matches — text offsets in the answer, row indices in the list —
// so the pane supplies `matchesFor` and this holds everything else, the way
// vim/keys.mjs holds one keymap for both rather than two that can drift.
Item {
  id: finder

  // Sorted positions the pattern matches, from the pane:
  // function (pattern, wholeWord) -> [int].
  property var matchesFor: null

  property var find: Find.IDLE
  property string lastPattern: ""              // what n and N repeat
  property bool lastBackward: false
  property bool lastWholeWord: false           // set by *, which will not match inside a word
  property int anchor: 0                       // where the reader was when the prompt opened

  readonly property bool active: find.active
  readonly property string prompt: Find.promptText(find)

  signal moved(int target)                     // go here
  signal dropped(int target)                   // the search was called off; put the cursor back

  function open (backward, from) {
    anchor = from
    find = Find.openFind(backward)
  }

  function close () {
    find = Find.IDLE
  }

  // Leaving the pane drops the search as well as the prompt, so a highlight
  // never outlives the reading that wanted it.
  function forget () {
    lastPattern = ""
    lastWholeWord = false
    close()
  }

  function matches (pattern, wholeWord) {
    const found = matchesFor ? matchesFor(pattern, wholeWord === true) : []
    return found || []
  }

  /**
   * `*` and `#`: search for `word` without opening a prompt, and land on the
   * next one. n and N carry on from there, and the matches stay lit, because
   * this leaves exactly the state an accepted prompt would have.
   */
  function searchWord (word, from, backward) {
    if (!word) return
    lastPattern = word
    lastBackward = backward === true
    lastWholeWord = true
    go(Find.nextMatch(matches(word, true), from, lastBackward, 1))
  }

  /**
   * One keystroke while the prompt is open; true when it was consumed. While the
   * pattern is still being typed the search runs from the anchor and counts a
   * match sitting on it, as vim's incsearch does — the reader has not moved, so
   * the match under the cursor is the one to show.
   */
  function feed (event) {
    if (!find.active) return false
    const before = find
    const step = Find.feedFind(before, Chord.findKey(event), event.text)
    find = step.state

    if (step.action === "typing") {
      if (find.pattern === "") dropped(anchor)
      else go(Find.matchFrom(matches(find.pattern), anchor, find.backward, true))
    } else if (step.action === "accept") {
      lastPattern = before.pattern
      lastBackward = before.backward
      lastWholeWord = false          // a typed pattern matches inside a word; * does not
      go(Find.matchFrom(matches(before.pattern), anchor, before.backward, false))
    } else if (step.action === "cancel") {
      dropped(anchor)
    }
    return true
  }

  // Where n and N land, without going there — so the answer pane can treat them
  // as motions and y3n can yank to the third match. N reverses the direction the
  // search was made in, as vim's does.
  function target (reverse, from, times) {
    if (!lastPattern) return -1
    const backward = reverse ? !lastBackward : lastBackward
    return Find.nextMatch(matches(lastPattern, lastWholeWord), from, backward, times)
  }

  function step (reverse, from, times) {
    go(target(reverse, from, times))
  }

  function go (target) {
    if (target >= 0) moved(target)
  }
}
