import QtQuick
import Quickshell.Io
import "../lib/search.mjs" as SearchLib

// One query and its pages. `pages` caches each fetched page as { rows, next },
// so l fetches at most once per page and h never fetches.
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

  function handoffText (index) {
    return SearchLib.handoffText(lastQuery, currentPage ? currentPage.rows : [], index)
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
    const page = { rows: rows, next: payload.next ?? null }
    if (!wasPaging) {
      pages = [page]
      showPage(0)
      return
    }
    // `h` is not blocked while a page loads, so the reader may have stepped
    // back by the time it lands. Then it only joins the cache — jumping to
    // it would yank them forward to a page they did not ask for.
    const stillWaiting = pageIndex === pages.length - 1
    pages = [...pages, page]
    if (stillWaiting) showPage(pages.length - 1)
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
