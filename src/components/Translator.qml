import QtQuick
import "../lib/translate.mjs" as TranslateLib

// Quick translation: what was asked to be translated, the translation, and the
// bin/ask --translate run that makes it. The shape of SearchSession, with one
// process per request: a stopped Process still reports its empty stream as an
// unreadable answer, and a request replaced by a newer one — gt pressed again
// before the first came back — must not land as an error in its place.
Item {
  id: translator

  property string askPath: ""

  property bool open: false
  property string source: ""                   // the text asked about
  property string text: ""                     // its translation
  property string target: ""                   // the language it went into, as a code
  property string status: "idle"               // idle | translating | done | error
  property string errorMessage: ""
  property real startedAt: 0
  property int requestId: 0                    // the one whose answer is wanted

  // The model list for the agent that translates, as AiSession keeps Ask's.
  property string modelAgent: ""
  property var models: null
  onModelAgentChanged: probeModels()

  readonly property string targetLabel: TranslateLib.targetLabel(target)

  function translate (value, into) {
    const clean = String(value || "").trim()
    if (!clean || !askPath) return false
    requestId = requestId + 1
    open = true
    source = clean
    text = ""
    target = into
    status = "translating"
    errorMessage = ""
    startedAt = Date.now()
    const run = runComponent.createObject(translator, { requestId: requestId })
    run.start([askPath, "--translate", "--json", JSON.stringify({ text: clean, target: into })])
    return true
  }

  // Closing disowns the request still running: its answer, if it comes, has no
  // one left to read it.
  function close () {
    requestId = requestId + 1
    open = false
    status = "idle"
    source = ""
    text = ""
    errorMessage = ""
  }

  function land (id, payload) {
    if (id !== requestId) return
    if (payload.ok) {
      text = String(payload.text || "").trim()
      status = "done"
    } else {
      errorMessage = payload.message || "the translation failed"
      status = "error"
    }
  }

  function probeModels () {
    if (!askPath || !modelAgent) return
    if (modelsProcess.running) return          // the handler starts the newer one
    if (models && models.agent === modelAgent) return
    modelsProcess.requestedAgent = modelAgent
    modelsProcess.start([askPath, "--models", "--json", JSON.stringify({ agent: modelAgent })])
  }

  Component {
    id: runComponent

    JsonProcess {
      id: run

      property int requestId: 0

      onParsed: payload => {
        translator.land(run.requestId, payload)
        run.destroy()
      }
      onUnreadable: raw => {
        translator.land(run.requestId, { ok: false, message: raw === "" ? "the agent said nothing" : "could not read the translation" })
        run.destroy()
      }
    }
  }

  JsonProcess {
    id: modelsProcess

    property string requestedAgent: ""

    // As AiSession's: an answer for an agent no longer chosen is dropped, and
    // exiting starts the probe again for whichever one is chosen now.
    function keep (result) {
      if (requestedAgent !== translator.modelAgent) return
      translator.models = { agent: requestedAgent, models: result.models || [], message: result.message || "" }
    }

    onParsed: payload => modelsProcess.keep(payload)
    onUnreadable: modelsProcess.keep({ models: [], message: "could not read the model list" })
    onExited: Qt.callLater(translator.probeModels)
  }
}
