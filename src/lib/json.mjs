// Reading one of our own JSON files: the config, the query ring, the saved
// conversations. Every one of them is hand-editable, so nothing here throws —
// an unreadable file is an empty one, and a typo costs one setting rather than
// the panel. Kept in the subset QML's engine shares with node.

/** File text -> the object it holds; anything else is no object at all. */
export function parseObject (source) {
  if (typeof source !== 'string' || source.trim() === '') return {}
  try {
    const parsed = JSON.parse(source)
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
  } catch (error) {
    return {}
  }
}

/** A stored value read as text; anything else is ''. */
export function asText (value) {
  return typeof value === 'string' ? value : ''
}

/** A stored list under `key`, or [] — how both rings read their file. */
export function listUnder (source, key) {
  const value = parseObject(source)[key]
  return Array.isArray(value) ? value : []
}
