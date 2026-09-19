// Who answers, given what discovery found: the agent Ask uses, the one that
// translates, the model each is given, and the next one shift+tab moves to.

import { agentId, modelId, readModels, readEfforts } from './config.mjs'
import { DEFAULT_AGENT, SAME_AS_ASK, EFFORT_CHOICES } from './choices.mjs'

// Who answers, given what discovery found: the installed ids, and the one that
// stands in for 'default'. Read by the model row and by the model handed to the
// CLI, which must agree.
export function agentChoices (agents) {
  const known = agents && Array.isArray(agents.agents) ? agents.agents : []
  const ids = []
  for (let i = 0; i < known.length; i++) ids.push(known[i].id)
  return {
    known: known,
    ids: ids,
    defaultId: agents && typeof agents.default === 'string' ? agents.default : ''
  }
}

export function modelSelection (settings, agent, catalog, stored = 'chatModels') {
  const options = ['default']
  const discovered = catalog && catalog.agent === agent && Array.isArray(catalog.models) ? catalog.models : []
  for (const choice of discovered) {
    const id = modelId(choice)
    if (id && options.indexOf(id) === -1) options.push(id)
  }
  const saved = readModels(settings[stored])[agent] || ''
  return { options: options, value: options.indexOf(saved) !== -1 ? saved : 'default' }
}

/** The effort row: 'default', then the levels the agent's flag takes, if any. */
export function effortSelection (settings, agent, stored = 'chatEfforts') {
  const levels = EFFORT_CHOICES[agent]
  const options = ['default'].concat(Array.isArray(levels) ? levels : [])
  const saved = readEfforts(settings[stored])[agent] || ''
  return { options: options, value: options.indexOf(saved) !== -1 ? saved : 'default' }
}

/**
 * Shift+tab: the installed agent after the one answering now, wrapping. From
 * 'default' it counts from the agent that stands in for it, so the first press
 * always changes who answers. Null when there is nothing else to switch to.
 */
export function nextAgent (agents, chatAgent) {
  const { ids, defaultId } = agentChoices(agents)
  if (ids.length === 0) return null
  const current = agentId(chatAgent) === DEFAULT_AGENT ? defaultId : agentId(chatAgent)
  const at = ids.indexOf(current)
  const next = ids[(at + 1) % ids.length]
  return next === current ? null : next
}

/** The model the panel may pass to the CLI; empty deliberately means its default. */
export function selectedModel (settings, agents = null, catalog = null) {
  const choices = agentChoices(agents)
  const requested = agentId(settings.chatAgent)
  const agent = requested !== DEFAULT_AGENT && choices.ids.indexOf(requested) !== -1
    ? requested : choices.defaultId
  const selected = modelSelection(settings, agent, catalog).value
  return selected === 'default' ? '' : selected
}

/** The effort the next question is asked at; empty is the CLI's own. */
export function selectedEffort (settings, agents = null) {
  const choices = agentChoices(agents)
  const requested = agentId(settings.chatAgent)
  const agent = requested !== DEFAULT_AGENT && choices.ids.indexOf(requested) !== -1
    ? requested : choices.defaultId
  const selected = effortSelection(settings, agent).value
  return selected === 'default' ? '' : selected
}

/**
 * Who translates: the agent chosen under Translate, or — as it is by default —
 * whoever answers Ask. '' before discovery has found anyone.
 */
export function translateAgentOf (settings, agents = null) {
  const choices = agentChoices(agents)
  const chosen = settings ? settings.translateAgent : SAME_AS_ASK
  if (chosen && chosen !== SAME_AS_ASK && choices.ids.indexOf(chosen) !== -1) return chosen
  const ask = settings ? agentId(settings.chatAgent) : DEFAULT_AGENT
  return ask !== DEFAULT_AGENT && choices.ids.indexOf(ask) !== -1 ? ask : choices.defaultId
}
