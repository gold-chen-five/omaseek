// What the SearXNG rows say after they ran something: the engines test, a timed
// search, and the version check — each a line of text for the row's hint.

/**
 * What the endpoint test found, from `bin/search --test`, as the Test row's
 * hint: how long a real query took and which engine gave what.
 */
// SearXNG prefixes an engine it has parked with "Suspended: "; inside the
// brackets after a row count, the prefix says nothing the brackets do not.
export function shortReason (reason) {
  const text = String(reason)
  return text.indexOf('Suspended: ') === 0 ? text.slice('Suspended: '.length) : text
}

export function endpointTestText (test) {
  if (!test) return ''
  if (test.running) return 'asking each engine in turn…'
  if (!test.ok) return test.message || 'SearXNG did not answer'
  const parts = []
  const answers = test.engines || {}
  const named = {}
  for (const name in answers) {
    const answer = answers[name]
    // A count alone is what --test printed before it timed each engine.
    const rows = typeof answer === 'number' ? answer : answer.rows
    const ms = typeof answer === 'number' ? null : answer.ms
    const reason = typeof answer === 'number' ? '' : (answer.reason || '')
    named[name] = true
    // The reason rides along with the count: an engine that CAPTCHAs answers in
    // 3 ms with no rows, which on its own reads like the fastest of the lot.
    const timed = `${name} ${rows}` + (ms === null || ms === undefined ? '' : ` in ${ms} ms`)
    parts.push(reason ? `${timed} (${shortReason(reason)})` : timed)
  }
  const silent = test.unresponsive || []
  for (let i = 0; i < silent.length; i++) {
    // An engine that was asked is already listed, with its time and its reason.
    if (named[silent[i].engine]) continue
    parts.push(`${silent[i].engine}: ${silent[i].reason}`)
  }
  if (Object.keys(answers).length === 0 && silent.length === 0) parts.push('no rows')
  return parts.join(' · ')
}

/**
 * The Search speed row's hint, from `bin/search --time`: one real search, every
 * engine at once, which is the wait a keypress actually buys. The engine times
 * from the test row are each engine alone and never add up to this.
 */
export function searchSpeedText (speed) {
  if (!speed) return 'time one real search: every engine at once, as a keypress sends it'
  if (speed.running) return 'searching…'
  if (!speed.ok) return speed.message || 'SearXNG did not answer'
  const silent = speed.unresponsive || []
  const parts = [`${speed.ms} ms for ${speed.rows} rows`]
  for (let i = 0; i < silent.length; i++) parts.push(`${silent[i].engine}: ${silent[i].reason}`)
  return parts.join(' · ')
}

/**
 * The Update row's hint: the running version, and whether it is the newest
 * image, from `bin/search --version`. The date is the part a person compares;
 * the commit after it is only noise here.
 */
export function versionText (version) {
  if (!version) return 'pull the latest image; restart only when it changed'
  if (version.checking) return 'checking the running version…'
  if (!version.ok) return 'not running — start it to see its version'
  const running = version.version ? String(version.version).split('+')[0] : 'unknown version'
  const latest = version.latest ? String(version.latest).split('-')[0] : ''
  if (version.current === true) return `${running} — the latest`
  if (version.current === false) return `${running} running · ${latest} available — update`
  return `${running} running · could not check for a newer one`
}
