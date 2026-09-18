// Text into the rich-text HTML a QML TextEdit renders: the answer's Markdown
// and the lit matches of a `/` search both escape it first.

export function escapeHtml (text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}
