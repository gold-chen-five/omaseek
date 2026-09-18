// The Ask, Translate and Display sections: who answers and with which model,
// who translates and into what, and how lines and pages are numbered.

import {
  LAUNCHER_CHOICES, DEFAULT_AGENT, SAME_AS_ASK, LINE_NUMBER_CHOICES, PAGE_NUMBER_CHOICES
} from './choices.mjs'
import { agentChoices, modelSelection, translateAgentOf } from './agents.mjs'
import { TRANSLATE_LANGUAGES, FOLLOW_SEARCH, defaultTarget, targetLabel, readTarget } from '../translate/translate.mjs'

/** The agent, its model, streaming, and where a hand-off opens. */
export function askRows (settings, agents, catalog) {
  const { known, ids, defaultId } = agentChoices(agents)
  const chatAgent = settings.chatAgent === DEFAULT_AGENT || ids.indexOf(settings.chatAgent) !== -1
    ? settings.chatAgent
    : DEFAULT_AGENT
  const modelAgent = chatAgent !== DEFAULT_AGENT ? chatAgent : defaultId
  const model = modelSelection(settings, modelAgent, catalog)
  return [
    {
      key: 'chatAgent',
      type: 'choice',
      control: 'dropdown',       // seven-plus options: a list, not a row of chips
      label: 'Agent',
      hint: agents === null ? 'finding installed agents…'
        : known.length === 0 ? 'nothing installed — pick one with: omarchy default agent <name>'
        : agents.configured ? `default is ${defaultId}, from omarchy default agent`
        : `default is ${defaultId} — omarchy default agent is unset, so the first installed stands in`,
      options: [DEFAULT_AGENT].concat(ids),
      value: chatAgent
    },
    {
      key: 'chatModel:' + modelAgent,
      type: 'choice',
      control: 'dropdown',
      label: 'Model',
      hint: modelAgent ? `${modelAgent} — default uses the CLI's choice; applies next turn and to hand-offs`
        + (catalog && catalog.agent === modelAgent && catalog.message ? ` · ${catalog.message}` : '')
        : 'choose an installed agent first',
      options: model.options,
      value: model.value
    },
    {
      key: 'stream',
      type: 'toggle',
      label: 'Answer as it is written',
      hint: settings.stream
        ? 'the reply appears word by word, where the agent can do that'
        : 'the reply appears whole, once the agent has finished',
      action: settings.stream ? 'off' : 'on',   // what flipping it does
      value: settings.stream !== false
    },
    {
      key: 'launcher',
      type: 'choice',
      label: 'Hand off to',
      hint: 'where a hand-off opens the agent, with the text waiting unsent in its input',
      options: LAUNCHER_CHOICES,
      value: settings.launcher
    },
  ]
}

/** Into which language, and which agent and model translate. */
export function translateRows (settings, agents, translateCatalog) {
  const { ids } = agentChoices(agents)
  const translator = translateAgentOf(settings, agents)
  const translateModel = modelSelection(settings, translator, translateCatalog, 'translateModels')
  return [
    {
      key: 'translateLanguage',
      type: 'choice',
      control: 'dropdown',
      label: 'Translate into',
      hint: settings.translateLanguage === FOLLOW_SEARCH || !settings.translateLanguage
        ? 'into ' + targetLabel(defaultTarget(settings.searxngLanguage)) +
          ' — the search language, or 繁體中文 when that names none. Text already in it goes into English'
        : 'into ' + targetLabel(settings.translateLanguage) + '; text already in it goes into English',
      options: [FOLLOW_SEARCH].concat(TRANSLATE_LANGUAGES.map(language => language.code)),
      value: readTarget(settings.translateLanguage)
    },
    {
      key: 'translateAgent',
      type: 'choice',
      control: 'dropdown',
      label: 'Translate with',
      hint: translator
        ? (settings.translateAgent === SAME_AS_ASK || !settings.translateAgent
            ? translator + ' — whoever Ask uses; choose a quick one to translate faster'
            : translator + ' translates, whoever Ask uses')
        : 'no agent installed',
      options: [SAME_AS_ASK].concat(ids),
      value: settings.translateAgent && (settings.translateAgent === SAME_AS_ASK || ids.indexOf(settings.translateAgent) !== -1)
        ? settings.translateAgent : SAME_AS_ASK
    },
    {
      key: 'translateModel:' + translator,
      type: 'choice',
      control: 'dropdown',
      label: 'Translation model',
      hint: translator ? `${translator} — default uses the CLI's choice; a small, quick model translates fastest`
        + (translateCatalog && translateCatalog.agent === translator && translateCatalog.message ? ` · ${translateCatalog.message}` : '')
        : 'choose an installed agent first',
      options: translateModel.options,
      value: translateModel.value
    },
  ]
}

/** Line numbers and page numbers. */
export function displayRows (settings) {
  return [
    {
      key: 'lineNumbers',
      type: 'choice',
      label: 'Line numbers',
      hint: 'numbering in search results and AI responses',
      options: LINE_NUMBER_CHOICES,
      value: settings.lineNumbers
    },
    {
      key: 'pageNumbers',
      type: 'choice',
      label: 'Page numbers',
      hint: settings.pageNumbers === 'relative'
        ? 'the page squares count from the page on screen, so 3h and 5l read off the row'
        : 'the page squares carry their own page number',
      options: PAGE_NUMBER_CHOICES,
      value: settings.pageNumbers
    },
  ]
}
