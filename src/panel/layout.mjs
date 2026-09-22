// How big the card is, and how the reading pane and the translation split it.
// The sizes are the ones asked for; a screen too small for them clamps the card
// to itself less the gap Hyprland keeps round windows, so the card always fits,
// laptop or desktop. test/layout.test.mjs checks that against real screens.
// Indexed loops and plain Math only: this runs in QML's JS engine too.

export const CARD_WIDTH = 820                 // search or ask on its own
export const CARD_WIDTH_TRANSLATING = 1000    // wider while a translation is split off
export const CARD_HEIGHT = 560
export const READING_SHARE = 0.66             // of the card's inside, left of the translation

/**
 * { width, height } of the card on a screen of `screenWidth` × `screenHeight`
 * logical pixels, `gap` kept on every side. `space` is the theme's spacing
 * scale (Style.space); left out, sizes are taken as they are.
 */
export function cardSize (screenWidth, screenHeight, translating, gap, space) {
  const scaled = typeof space === 'function' ? space : px => px
  const room = edge => Math.max(0, edge - gap * 2)
  return {
    width: Math.min(scaled(translating ? CARD_WIDTH_TRANSLATING : CARD_WIDTH), room(screenWidth)),
    height: Math.min(scaled(CARD_HEIGHT), room(screenHeight))
  }
}

/** The reading pane's width inside a card `inner` wide: all of it, or its share beside a translation. */
export function readingWidth (inner, translating) {
  return translating ? Math.round(inner * READING_SHARE) : inner
}
