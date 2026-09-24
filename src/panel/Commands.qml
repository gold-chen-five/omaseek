import QtQuick
import Quickshell
import "../search/search.mjs" as SearchLib
import "../search/history.mjs" as History
import "../ask/sessions.mjs" as Sessions
import "../ask/transcript.mjs" as Transcript
import "../shared/states.mjs" as States
import "../shared/urls.mjs" as Urls

// What the field does with Enter and the arrows, and the actions that carry
// something from one half of the panel to the other: a result asked about, a
// passage searched for, a link opened. Each touches more than one store and
// then moves the keyboard, so they live beside the panel (`host`) rather than
// in any one store.
Item {
  id: commands

  property var host: null                      // Search.qml: panelMode, the field, focus, say, dismiss
  property var session: null
  property var queries: null
  property var ai: null
  property var translator: null
  property var config: null
  property var suggestions: null               // the dropdown under the search bar

  property int historyIndex: -1                // where the walk sits; -1 is what was typed
  property string historyDraft: ""             // what was typed, kept while the walk is away from it
  property bool applyingHistory: false         // a walk writing the field, not the reader typing
  property bool applyingSuggestion: false      // the dropdown writing the field, likewise

  // `searching` forces a search: gs on a title that happens to look like a
  // domain means "find this", not "go there".
  function runSearch (searching) {
    const input = host.input
    const query = input.text.trim()
    if (!query) return
    if (host.panelMode === States.PANEL.AI) {
      ai.ask(query.split(input.lineBreak).join("\n"))
      resetHistoryWalk()                       // ↑ starts again from the question just asked
      input.clear()                            // the question now lives in the transcript
      // Straight into the answer, as Enter in search goes to the results: the
      // reply is what is read next, and q there stops it. i, a or gi go back to
      // the field for the next question.
      host.focusResults()
      return
    }
    const flat = SearchLib.cleanQuery(query.split(input.lineBreak).join(" "))
    suggestions.clear()                        // searched: the list goes until the next thing typed
    // The field shows what is searched: stray spaces at either end, or a run of
    // them inside, are gone once Enter has read it.
    if (input.text !== flat) writeBar(flat)
    queries.remember(flat)                     // the arrows walk back to it next time
    resetHistoryWalk()
    // A pasted address is opened, as a browser's address bar would; anything
    // that is not unmistakably one (vue.js, README.md) is still searched.
    const address = searching === true ? "" : Urls.queryUrl(flat)
    if (address) {
      openUrl(address)
      return
    }
    session.search(flat)
    host.focusSearch("normal")                 // keep the query readable while results load
  }

  // ↑ ↓ past the field's first or last line, and U. The draft is what the reader
  // had typed: kept aside on the first step away and put back on the last step
  // home. An unchanged index means the walk had nowhere to go, which is how Down
  // at the draft still steps into the results. Search walks the queries it
  // searched; ask, the questions in its saved conversations.
  function walkHistory (delta) {
    const past = host.panelMode === States.PANEL.AI ? Sessions.pastQuestions(ai.sessions) : queries.queries
    if (historyIndex === -1) historyDraft = host.input.text
    const step = History.stepQuery(past, historyIndex, delta, historyDraft)
    if (step.index === historyIndex) return false
    historyIndex = step.index
    applyingHistory = true
    host.input.setQuery(step.text)
    applyingHistory = false
    return true
  }

  // ↓ ↑ and ctrl+n ctrl+p while the dropdown shows: the bar shows the row the
  // arrows are on, and back past either end what was typed — Enter searches it.
  function stepSuggestion (delta) {
    writeBar(suggestions.step(delta))
  }

  // A row clicked: searched straight away.
  function searchSuggestion (text) {
    writeBar(text)
    runSearch(true)
  }

  // The bar rewritten by the panel rather than typed: no new suggestions for it.
  function writeBar (text) {
    applyingSuggestion = true
    host.input.setQuery(text)
    applyingSuggestion = false
  }

  function resetHistoryWalk () {
    historyIndex = -1
    historyDraft = ""
  }

  // gt, gT, ctrl+t and the translate button: into the language set under
  // Translate, in the panel split off to the right; the keyboard stays put.
  function translateText (value) {
    const target = translator.targetFor(config.settings)
    if (translator.translate(value, target)) host.say("translating into " + translator.labelFor(target) + "…")
  }

  function translateBar () {
    translateText(host.input.text.split(host.input.lineBreak).join("\n"))
  }

  function yankResult (index, withTitle) {
    const text = session.yankText(index, withTitle)
    if (!text) return
    host.copyText(text)
    host.say(SearchLib.yankNotice(withTitle))
  }

  // gj: the result over in the ask bar. Deliberately unsent — a question still
  // has to be typed around the URL.
  function askAboutResult (index) {
    const url = session.yankText(index, false)
    if (!url) return
    if (host.panelMode !== States.PANEL.AI) host.toggleMode()
    host.input.setQuery(url + " ")
    host.focusSearch("insert")
  }

  // gj in the answer or the translation: the passage in the ask bar, the
  // cursor under it.
  function askAboutText (text) {
    const passage = SearchLib.passageForQuestion(text)
    if (!passage) return
    if (host.panelMode !== States.PANEL.AI) host.toggleMode()
    host.input.setQuery(passage)
    host.focusSearch("insert")
  }

  // gd: asked straight away, as Enter in the ask bar would — a draft typed
  // there stays where it is — and into the answer to read the reply.
  function askNow (text) {
    const question = String(text || "").trim()
    if (!question) return
    if (host.panelMode !== States.PANEL.AI) host.toggleMode()
    ai.ask(question)
    host.focusResults()
  }

  // gd on a result: its title and URL, the way Y copies them.
  function askNowResult (index) {
    askNow(session.yankText(index, true))
  }

  // ga and gA in the field: what was typed, as an editable draft in the agent.
  // gA puts first what gA below would hand off — the page's URLs in search, the
  // conversation in ask — so the draft reads as a question about it.
  function handOffBar (text, everything) {
    const bar = String(text || "").split(host.input.lineBreak).join("\n").trim()
    let draft = bar
    if (everything) {
      const below = host.panelMode === States.PANEL.AI
        ? Transcript.conversationText(ai.history) : session.handoffText(-1)
      draft = [String(below || "").trim(), bar].filter(part => part !== "").join("\n\n")
    }
    if (draft) ai.launch(draft)
  }

  // gd in the field: all of the bar is asked as Enter in the ask bar would,
  // and leaves it, since the question then lives in the transcript; a
  // selection is asked and the rest of the bar stays to be edited.
  function askFromBar (text, whole) {
    const question = String(text || "").split(host.input.lineBreak).join("\n").trim()
    if (!question) return
    askNow(question)
    if (whole) {
      resetHistoryWalk()
      host.input.clear()
    }
  }

  // gs: the other way. A selection is already a whole query, so this one runs.
  function searchFor (text) {
    if (!text) return
    if (host.panelMode !== States.PANEL.SEARCH) host.toggleMode()
    host.input.setQuery(text)
    runSearch(true)
  }

  function openResult (index) {
    if (index < 0 || index >= session.results.count) return
    openUrl(session.results.get(index).url)
  }

  // The browser takes the screen, so the panel steps aside.
  function openUrl (url) {
    if (!url) return
    host.dismiss()
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }
}
