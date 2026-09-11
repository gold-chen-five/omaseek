// Links under the cursor, for gx. Markdown links are found by the TextEdit
// itself; this finds the ones an agent wrote out bare. Only http(s) opens: an
// agent's text is not trusted to launch a file:// or javascript: URL.

export function isOpenable (url) {
  return /^https?:\/\/\S+$/i.test(String(url == null ? '' : url))
}

function count (s, ch) {
  let n = 0
  for (let i = 0; i < s.length; i++) if (s.charAt(i) === ch) n++
  return n
}

// Trailing punctuation belongs to the sentence; a closing bracket belongs to
// the URL only when the URL opened one, as in Rust_(programming_language).
function trim (url) {
  let end = url.length
  while (end > 0) {
    const body = url.slice(0, end)
    const c = body.charAt(end - 1)
    if ('.,;:!?'.indexOf(c) !== -1) { end--; continue }
    if (c === ')' && count(body, '(') < count(body, ')')) { end--; continue }
    if (c === ']' && count(body, '[') < count(body, ']')) { end--; continue }
    return body
  }
  return ''
}

/** The bare URL the cursor sits on, or ''. */
export function urlAt (text, pos) {
  const source = String(text == null ? '' : text)
  const re = /[^\s<>"'`]+/g
  let m
  while ((m = re.exec(source)) !== null) {
    const leading = /^[(\[]*/.exec(m[0])[0].length
    const token = trim(m[0].slice(leading))
    const url = urlFromSelection(token)
    const start = m.index + leading
    if (url && pos >= start && pos < start + token.length) return url
  }
  return ''
}

/** "https://www.rust-lang.org/learn" -> "rust-lang.org", for the status line. */
export function hostOf (url) {
  const m = /^https?:\/\/([^/?#]+)/i.exec(String(url == null ? '' : url))
  return m ? m[1].replace(/^www\./, '') : ''
}

/** A visual selection as a URL to open, or ''. A bare domain gets https://. */
export function urlFromSelection (text) {
  const raw = String(text == null ? '' : text).replace(/[\u2028\u2029\r\n]+/g, '').trim()
  if (!raw || /\s/.test(raw)) return ''
  const url = trim(raw.replace(/^[(<[]+/, ''))
  if (isOpenable(url)) return url
  if (/^[a-z][a-z0-9+.-]*:(?!\d)/i.test(url)) return ''       // some other scheme; host:8080 is a port
  const host = url.split(/[/?#]/)[0]
  if (/^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?$/i.test(host)) return 'https://' + url
  return ''
}


/** Link metadata from TextEdit.getFormattedText for the cursor's character. */
export function hrefFromHtml (html) {
  const match = /<a\b[^>]*\bhref=["']([^"']*)["']/i.exec(String(html || ''))
  if (!match) return ''
  return match[1].replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}
