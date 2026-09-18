// Quick translation (gt, gT, the translate button): the languages it goes
// into, and which one when none was chosen. Pure; under test. The language
// names the agent is given live in backend/omaseek/ask/prompts.py
// (TRANSLATE_LANGUAGES); the codes are mirrored there — change both.

// The code a setting stores, and how the page names it: in its own script, as
// a reader who wants it would look for it.
export const TRANSLATE_LANGUAGES = [
  { code: 'zh-TW', label: '繁體中文' },
  { code: 'zh-CN', label: '简体中文' },
  { code: 'en', label: 'English' },
  { code: 'ja', label: '日本語' },
  { code: 'ko', label: '한국어' },
  { code: 'fr', label: 'Français' },
  { code: 'de', label: 'Deutsch' },
  { code: 'es', label: 'Español' },
  { code: 'it', label: 'Italiano' },
  { code: 'pt', label: 'Português' },
  { code: 'ru', label: 'Русский' },
  { code: 'vi', label: 'Tiếng Việt' },
  { code: 'th', label: 'ไทย' }
]

export const FALLBACK_TARGET = 'zh-TW'
// The setting's first option: take the language from Search → Language / region.
export const FOLLOW_SEARCH = 'search language'

function known (code) {
  for (let i = 0; i < TRANSLATE_LANGUAGES.length; i++) if (TRANSLATE_LANGUAGES[i].code === code) return true
  return false
}

/**
 * The language a translation goes into when none was chosen: the one searches
 * are made in, as SearXNG's code names it (zh-TW, ja-JP, fr), else 繁體中文.
 * English is no target for text most often read in English, so it falls back
 * too, and 'default', 'auto' and 'all' name no language at all.
 */
export function defaultTarget (searxngLanguage) {
  const code = String(searxngLanguage == null ? '' : searxngLanguage).trim()
  if (known(code)) return code === 'en' ? FALLBACK_TARGET : code
  if (code === 'zh' || code === 'zh-HK') return 'zh-TW'
  const base = code.split('-')[0]
  if (base !== 'en' && base !== 'zh' && known(base)) return base
  return FALLBACK_TARGET
}

/** The target in force: the one chosen, or the one searches suggest. */
export function effectiveTarget (settings) {
  const chosen = settings ? settings.translateLanguage : ''
  if (chosen && chosen !== FOLLOW_SEARCH && known(chosen)) return chosen
  return defaultTarget(settings ? settings.searxngLanguage : '')
}

/** "繁體中文" for "zh-TW"; the code itself for one the table lacks. */
export function targetLabel (code) {
  for (let i = 0; i < TRANSLATE_LANGUAGES.length; i++) {
    if (TRANSLATE_LANGUAGES[i].code === code) return TRANSLATE_LANGUAGES[i].label
  }
  return String(code || '')
}

/** A stored target: a code from the table, else following search. */
export function readTarget (value) {
  const code = String(value == null ? '' : value).trim()
  return known(code) ? code : FOLLOW_SEARCH
}
