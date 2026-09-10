// Markdown -> the subset of HTML a QML TextEdit in RichText mode renders.
//
// Exists because a TextEdit can colour a *range* only in rich text, and the
// transcript needs two colours: the question bright, the reply quiet — the
// way Claude Code draws its own. Qt's Markdown mode has no such lever, so
// the agent's Markdown is converted here instead. Small on purpose: fenced
// code, headings, lists, blockquotes, paragraphs, and the inline marks that
// show up in an answer. Anything else stays visible as typed.
//
// Pure, and within the JS subset QML's engine shares with node: indexed
// loops, indexOf, and regexes without lookbehind.

export function escapeHtml (text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

/** Inline marks: code, bold, italic, links. Code first, so its contents are left alone. */
// `link` colours anchors: a TextEdit paints <a> in Qt's own link blue unless
// the tag says otherwise, and no theme this panel sits in has that blue in it.
export function inline (text, link = '') {
  const pieces = []
  const parts = escapeHtml(text).split('`')
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 1 && i < parts.length - 1) {
      pieces.push('<code>' + parts[i] + '</code>')
      continue
    }
    if (i % 2 === 1) pieces.push('`')            // an unclosed backtick is just a backtick
    pieces.push(
      parts[i]
        .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
        .replace(/__([^_]+)__/g, '<b>$1</b>')
        .replace(/(^|[^*\w])\*([^*\s][^*]*?)\*(?!\w)/g, '$1<i>$2</i>')
        .replace(/(^|[^_\w])_([^_\s][^_]*?)_(?!\w)/g, '$1<i>$2</i>')
        .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, link ? `<a href="$2" style="color:${link}">$1</a>` : '<a href="$2">$1</a>')
    )
  }
  return pieces.join('')
}

function block (tag, content, color) {
  const open = color ? `<${tag}><span style="color:${color}">` : `<${tag}>`
  const close = color ? `</span></${tag}>` : `</${tag}>`
  return open + content + close
}

/**
 * Markdown -> HTML. `color` wraps every block's text so the whole answer
 * carries one colour; `lead` is HTML placed before the first block's text
 * (the ● a reply starts with).
 */
export function toHtml (markdown, { color = '', lead = '', link = '' } = {}) {
  const lines = String(markdown ?? '').replace(/\r\n?/g, '\n').split('\n')
  const out = []
  let paragraph = []
  let list = null                               // { tag, items }
  let first = true

  const withLead = content => {
    if (!first) return content
    first = false
    return lead + content
  }
  const flushParagraph = () => {
    if (paragraph.length === 0) return
    out.push(block('p', withLead(inline(paragraph.join(' '), link)), color))
    paragraph = []
  }
  const flushList = () => {
    if (!list) return
    let items = ''
    for (let i = 0; i < list.items.length; i++) {
      items += block('li', (i === 0 ? withLead(inline(list.items[i], link)) : inline(list.items[i], link)), color)
    }
    out.push(`<${list.tag}>${items}</${list.tag}>`)
    list = null
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (/^\s*```/.test(line)) {
      flushParagraph(); flushList()
      const code = []
      i++
      while (i < lines.length && !/^\s*```/.test(lines[i])) { code.push(lines[i]); i++ }
      out.push(block('pre', withLead(escapeHtml(code.join('\n'))), color))
      continue
    }

    const heading = /^(#{1,6})\s+(.*)$/.exec(line)
    if (heading) {
      flushParagraph(); flushList()
      const level = Math.min(4, heading[1].length + 1)   // h1 in a chat is shouting
      out.push(block('h' + level, withLead(inline(heading[2], link)), color))
      continue
    }

    const item = /^\s*(?:[-*+]|\d+[.)])\s+(.*)$/.test(line) ? /^\s*(?:[-*+]|\d+[.)])\s+(.*)$/.exec(line) : null
    if (item) {
      flushParagraph()
      const tag = /^\s*\d/.test(line) ? 'ol' : 'ul'
      if (!list || list.tag !== tag) { flushList(); list = { tag: tag, items: [] } }
      list.items.push(item[1])
      continue
    }

    const quote = /^\s*>\s?(.*)$/.exec(line)
    if (quote) {
      flushParagraph(); flushList()
      out.push(block('blockquote', withLead(inline(quote[1], link)), color))
      continue
    }

    if (line.trim() === '') {
      flushParagraph(); flushList()
      continue
    }

    if (list && /^\s{2,}/.test(line)) {        // a wrapped list item continues
      list.items[list.items.length - 1] += ' ' + line.trim()
      continue
    }
    flushList()
    paragraph.push(line.trim())
  }
  flushParagraph(); flushList()
  return out.join('')
}

/**
 * The conversation as one rich-text document. A question is bright after a
 * dim prompt glyph; a reply is quiet after a small dot — Claude Code's own
 * layout, which is what people reading this already know.
 */
export function renderTranscript (turns, {
  question = '#ffffff', answer = '#cccccc', glyph = '#888888', error = '#e06c75', link = '', dotSize = 0
} = {}) {
  const dot = dotSize > 0 ? `font-size:${dotSize}px;` : ''
  const parts = []
  for (let i = 0; i < (turns || []).length; i++) {
    const turn = turns[i]
    if (turn.role === 'user') {
      parts.push(`<p><span style="color:${glyph}">&gt; </span><b><span style="color:${question}">${escapeHtml(turn.text)}</span></b></p>`)
    } else if (turn.role === 'error') {
      // What went wrong, where the answer would have been.
      parts.push(`<p><span style="color:${error}">⚠ ${escapeHtml(turn.text)}</span></p>`)
    } else {
      parts.push(toHtml(turn.text, {
        color: answer,
        link: link,
        lead: `<span style="color:${glyph};${dot}">● </span>`
      }))
    }
  }
  return parts.join('')
}
