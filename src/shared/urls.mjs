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
function trimSentenceEnd (url) {
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
    const token = trimSentenceEnd(m[0].slice(leading))
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
  const url = trimSentenceEnd(raw.replace(/^[(<[]+/, ''))
  if (isOpenable(url)) return url
  if (/^[a-z][a-z0-9+.-]*:(?!\d)/i.test(url)) return ''       // some other scheme; host:8080 is a port
  const host = url.split(/[/?#]/)[0]
  if (/^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(:\d+)?$/i.test(host)) return 'https://' + url
  return ''
}


// Domains a bare query is opened as rather than searched for. A list, not any
// letters: vue.js, README.md (Moldova), main.py (Paraguay) or main.rs (Serbia)
// is a question about a file, not an address — with a path (docs.rs/tokio) it
// opens whatever the domain.
const WEB_TLDS = ('com org net io dev app ai co gov edu mil int info biz me tv xyz tech site ' +
  'online blog page cloud wiki news link zone gg to fm im ly uk us eu de fr jp cn tw hk ' +
  'kr in ca au nz nl be se no fi dk ch at it es pt ie ru br mx ar za sg').split(' ')

/**
 * What the search field holds, as an address to open instead of searched for,
 * or ''. Only the whole query counts, and only when it is unmistakably one: an
 * http(s) URL, www.…, a common web domain (rust-lang.org), any domain with a
 * path or port (docs.rs/tokio), or localhost / an IP with a port (over http).
 */
export function queryUrl (text) {
  const raw = String(text == null ? '' : text).trim()
  if (!raw || /\s/.test(raw)) return ''
  if (isOpenable(raw)) return raw
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)) return ''          // another scheme
  const m = /^([^/?#]+)([/?#].*)?$/.exec(raw)
  if (!m) return ''
  const host = m[1]
  const rest = m[2] || ''
  if (/^(localhost|\d{1,3}(\.\d{1,3}){3}):\d{1,5}$/i.test(host)) return 'http://' + raw
  const domain = /^((?:[a-z0-9-]+\.)+([a-z]{2,}))(:\d{1,5})?$/i.exec(host)
  if (!domain) return ''
  const known = WEB_TLDS.indexOf(domain[2].toLowerCase()) !== -1
  const path = rest.length > 1 && rest.charAt(0) === '/'
  return known || /^www\./i.test(host) || domain[3] || path ? 'https://' + raw : ''
}

/** Link metadata from TextEdit.getFormattedText for the cursor's character. */
export function hrefFromHtml (html) {
  const match = /<a\b[^>]*\bhref=["']([^"']*)["']/i.exec(String(html || ''))
  if (!match) return ''
  return match[1].replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
}
