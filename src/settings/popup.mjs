// Where a dropdown's list opens, so it stays on screen. Pure, under test.
//
// Omarchy's Dropdown always opens below its trigger at up to eight rows, and
// its Popup is not kept inside the window: a dropdown low in the settings page
// ran off the bottom of the screen. The panel's window is the whole screen, so
// the window is the bound.

/**
 * `triggerTop` is the trigger's top in window coordinates. Returns the list's
 * `y`, relative to the trigger's top, and the `height` it gets: below when it
 * fits, else on whichever side has more room, shrunk to that room (the list
 * scrolls). Never shorter than one row while a row fits anywhere.
 */
export function placePopup ({
  triggerTop = 0, triggerHeight = 0, windowHeight = 0, natural = 0, gap = 0, margin = 0, minimum = 0
} = {}) {
  const below = windowHeight - (triggerTop + triggerHeight + gap) - margin
  const above = triggerTop - gap - margin
  if (natural <= below || below >= above) {
    const height = Math.max(Math.min(natural, below), Math.min(natural, minimum))
    return { y: triggerHeight + gap, height: height, above: false }
  }
  const height = Math.max(Math.min(natural, above), Math.min(natural, minimum))
  return { y: -gap - height, height: height, above: true }
}
