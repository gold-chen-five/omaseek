// One named colour from the theme's colors.toml. The shell's Color keeps only
// foreground, background, accent, urgent and muted; a theme defines more
// (yellow, magenta, green, ...), and this reads them the way Color.qml does.

/** colors.toml text + a key like "yellow" -> "#rrggbb", or '' when absent. */
export function paletteColor (raw, name) {
  const lines = String(raw == null ? '' : raw).split('\n')
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m && m[1] === name) return m[2]
  }
  return ''
}
