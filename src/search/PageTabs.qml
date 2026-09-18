import QtQuick
import qs.Commons
import "../shared"
import "pager.mjs" as Pager

// The pages of results as numbered squares, the one on screen filled — the
// mouse's h, l and 5gp. The last square fetches the page after the ones held,
// which is the only one of them that costs a request. Pages accumulate as they
// are read, so past a rowful this shows a window around the current page.
Item {
  id: tabs

  property int pageCount: 0
  property int current: 0                      // 0-based, as the session counts them
  property bool hasNext: false
  property bool loading: false
  // Follows the line-numbers setting: relative counts the squares from the page
  // being read, anything else numbers them plainly.
  property string numbering: "absolute"

  readonly property real squareSize: Math.round(Style.font.body * 2)
  readonly property var window: Pager.pageWindow(current, pageCount, 10)
  // A Repeater counts; the window says which page each square stands for.
  readonly property int shown: Math.max(0, window.end - window.start)

  signal picked(int page)                      // 1-based: the page to show
  signal nextRequested()

  implicitHeight: squareSize
  height: visible ? implicitHeight : 0

  Row {
    anchors.left: parent.left
    spacing: Style.spacing.xs

    Repeater {
      model: tabs.shown

      TabSquare {
        id: square

        required property int index

        readonly property int page: tabs.window.start + index + 1

        text: Pager.pageLabel(page, tabs.current + 1, tabs.numbering)
        tooltipText: "page " + page
        selected: page === tabs.current + 1

        onClicked: tabs.picked(square.page)
      }
    }

    // The page not fetched yet: the same request `l` makes at the end.
    TabSquare {
      visible: tabs.hasNext
      text: "›"
      tooltipText: tabs.loading ? "fetching the next page…" : "next page"
      opacity: tabs.loading ? 0.5 : 1

      onClicked: if (!tabs.loading) tabs.nextRequested()
    }
  }
}
