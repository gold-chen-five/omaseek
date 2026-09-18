import QtQuick
import "search.mjs" as SearchLib
import "../core"

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
  // Why the page after this one failed to load. Its continuation is kept, so
  // `l` asks again; "" when nothing failed.
  property string pageError: ""
  // Where a `5gp` jump is heading, 1-based; 0 when nothing is being jumped to.
  // Pages come one request at a time, so the jump is a chain of them.
  property int pageTarget: 0

  readonly property var currentPage: pages.length > 0 ? pages[pageIndex] : null
  readonly property int pageCount: pages.length
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
    searchProcess.start([backendPath, query])
  }

  // `l` — forward a page, from cache when we have already been there. A count
  // (`5l`) is the same walk as a jump, so it goes through goToPage.
  function nextPage (count) {
    const step = count === undefined ? 1 : Math.max(1, count)
    if (step > 1) {
      goToPage(pageIndex + 1 + step)
      return
    }
    if (loadingPage || status === "loading") return
    if (pageTarget > 0 && pages.length >= pageTarget) pageTarget = 0
    if (pageIndex + 1 < pages.length) {
      showPage(pageIndex + 1)
      return
    }
    if (!currentPage || !currentPage.next) return
    pageError = ""
    loadingPage = true
    searchProcess.start([backendPath, "--next", JSON.stringify(currentPage.next)])
  }

  // `h` — back a page, `3h` three. Always cached, so this never hits the network.
  function previousPage (count) {
    const step = count === undefined ? 1 : Math.max(1, count)
    pageTarget = 0                             // stepping by hand ends a jump
    if (hasPrevious) showPage(Math.max(0, pageIndex - step))
  }

  // `5gp` — page five. Cached pages are instant; the rest are fetched in turn,
  // since each page's continuation only comes with the page before it.
  function goToPage (number) {
    if (status !== "ok") return
    const target = SearchLib.pageJumpTarget(number, pages.length)
    if (target <= pages.length) {
      pageTarget = 0
      showPage(target - 1)
      return
    }
    if (loadingPage) return
    pageTarget = target
    showPage(pages.length - 1)                 // fetching carries on from the last one held
    nextPage()
  }

  function handoffText (index) {
    return SearchLib.handoffText(currentPage ? currentPage.rows : [], index)
  }

  // The row a reading key acts on, from the page on screen. The list raises an
  // index; what is behind it is this store's to know.
  function rowAt (index) {
    const rows = currentPage ? currentPage.rows : []
    return index >= 0 && index < rows.length ? rows[index] : null
  }

  function yankText (index, withTitle) {
    return SearchLib.resultYankText(rowAt(index), withTitle)
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
    pageError = ""
    pageTarget = 0
  }

  function showPage (index) {
    if (index < 0 || index >= pages.length) return
    pageIndex = index
    pageError = ""
    resultsModel.clear()
    for (const row of pages[index].rows) resultsModel.append(row)
    pageShown()
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
        // The rows past here were never fetched, so this is not the end: the
        // continuation stays and `l` retries it.
        failPage(message)
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

    // Mid-jump: ask for the next one, or stop here when the pages ran out.
    if (pageTarget > 0) {
      if (pages.length < pageTarget && page.next) nextPage()
      else {
        const landed = Math.min(pageTarget, pages.length)
        pageTarget = 0
        showPage(landed - 1)
      }
    }
  }

  // Said only on the last page: stepped back with h, the reader's `l` means the
  // cached page in front, and the next one to fetch can fail again later.
  function failPage (message) {
    pageTarget = 0                             // a jump stops where it broke
    if (pageIndex === pages.length - 1) pageError = message
  }

  function fail (message) {
    if (loadingPage) {
      loadingPage = false
      failPage(message)                        // the page on screen is still good
      return
    }
    status = "error"
    errorMessage = message
  }

  ListModel { id: resultsModel }

  JsonProcess {
    id: searchProcess

    onParsed: payload => session.apply(payload)
    onUnreadable: raw => session.fail(raw === "" ? "Search returned nothing" : "Could not read search output")
  }
}
