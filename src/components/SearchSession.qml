import QtQuick
import Quickshell.Io
import "../lib/search.mjs" as SearchLib

// One query and its pages.
//
// Results are paged, not scrolled. `pages` caches every page fetched for the
// current query as { rows, next }, where `next` is the payload bin/search
// wants echoed back for the page after — so `l` fetches at most once per page
// and `h` never fetches at all. The ListModel the list paints is sliced from
// that cache, one page at a time.
Item {
  id: session

  property string backendPath: ""

  property string status: "idle"               // idle | loading | ok | empty | error
  property string errorMessage: ""
  property string lastQuery: ""
  property string backend: ""                  // which backend answered, as it names itself
  property var pages: []
  property int pageIndex: 0
  property bool loadingPage: false

  readonly property var currentPage: pages.length > 0 ? pages[pageIndex] : null
  readonly property bool hasNext: currentPage ? (pageIndex + 1 < pages.length || currentPage.next !== null) : false
  readonly property bool hasPrevious: pageIndex > 0
  readonly property alias results: resultsModel

  signal pageShown()                           // the model was refilled; put the cursor back on top
  signal landed()                              // a fresh search has rows to walk
  signal engineDown(string reason)             // the instance is not there — nothing to read past
  signal engineUp()

  function search (query) {
    lastQuery = query
    status = "loading"
    errorMessage = ""
    resetPages()
    resultsModel.clear()
    fetch([backendPath, query])
  }

  // `l` — forward a page, from cache when we have already been there.
  function nextPage () {
    if (loadingPage || status === "loading") return
    if (pageIndex + 1 < pages.length) {
      showPage(pageIndex + 1)
      return
    }
    if (!currentPage || !currentPage.next) return
    loadingPage = true
    fetch([backendPath, "--next", JSON.stringify(currentPage.next)])
  }

  // `h` — back a page. Always cached, so this never hits the network.
  function previousPage () {
    if (hasPrevious) showPage(pageIndex - 1)
  }

  function reset () {
    cancel()
    status = "idle"
    errorMessage = ""
    lastQuery = ""
    resetPages()
    resultsModel.clear()
  }

  function cancel () { searchProcess.running = false }

  function resetPages () {
    pages = []
    pageIndex = 0
    loadingPage = false
  }

  function showPage (index) {
    if (index < 0 || index >= pages.length) return
    pageIndex = index
    resultsModel.clear()
    for (const row of pages[index].rows) resultsModel.append(row)
    pageShown()
  }

  function fetch (command) {
    searchProcess.running = false
    searchProcess.command = command
    searchProcess.running = true
  }

  // The current page keeps its rows and stops offering a next one.
  function closeCurrentPage () {
    pages = pages.map((page, i) => i === pageIndex ? { rows: page.rows, next: null } : page)
  }

  function apply (payload) {
    const wasPaging = loadingPage
    loadingPage = false

    if (!payload.ok) {
      const message = SearchLib.describeError(payload)
      if (payload.setup === true) {
        // Whether this was a fresh search or a page turn: ask, do not report.
        status = "idle"
        engineDown(message)
        return
      }
      if (wasPaging) {
        closeCurrentPage()
        errorMessage = message
        return
      }
      resultsModel.clear()
      status = "error"
      errorMessage = message
      return
    }

    engineUp()
    const rows = SearchLib.mergeResults([], payload.results)
    if (rows.length === 0) {
      if (wasPaging) {
        closeCurrentPage()                     // an empty page past the end: stay put
        return
      }
      resultsModel.clear()
      status = "empty"
      return
    }

    status = "ok"
    errorMessage = ""
    backend = payload.backend ?? ""
    pages = wasPaging ? [...pages, { rows: rows, next: payload.next ?? null }] : [{ rows: rows, next: payload.next ?? null }]
    showPage(pages.length - 1)
    if (!wasPaging) landed()
  }

  function fail (message) {
    loadingPage = false
    status = "error"
    errorMessage = message
  }

  ListModel { id: resultsModel }

  Process {
    id: searchProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const raw = String(text ?? "").trim()
        if (!raw) {
          session.fail("Search returned nothing")
          return
        }
        try {
          session.apply(JSON.parse(raw))
        } catch (error) {
          session.fail("Could not read search output")
        }
      }
    }
  }
}
