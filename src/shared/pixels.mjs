// Sizes that land on whole device pixels. At a fractional scale (1.25) a frame
// 30 logical pixels tall is 37.5 device pixels, and its bottom border straddles
// two rows: drawn one row thick or two depending on when the frame was built,
// so the same bar showed a heavier bottom edge until something rebuilt it.
// Indexed loops and plain Math only: this runs in QML's JS engine too.

/** `value` rounded to the nearest whole number of device pixels at `ratio`. */
export function snapToDevice (value, ratio) {
  const r = ratio > 0 ? ratio : 1
  return Math.round(value * r) / r
}
