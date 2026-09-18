import QtQuick
import qs.Commons
import qs.Ui
import "../lib/pager.mjs" as Pager

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
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

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

      Button {
        id: square

        required property int index

        readonly property int page: tabs.window.start + index + 1

        width: tabs.squareSize
        height: tabs.squareSize
        text: String(page)
        tooltipText: "page " + page
        bordered: true
        selected: page === tabs.current + 1
        foreground: tabs.foreground
        accent: tabs.accent
        fontFamily: tabs.fontFamily
        fontSize: Style.font.caption

        onClicked: tabs.picked(square.page)
      }
    }

    // The page not fetched yet: the same request `l` makes at the end.
    Button {
      visible: tabs.hasNext
      width: tabs.squareSize
      height: tabs.squareSize
      text: "›"
      tooltipText: tabs.loading ? "fetching the next page…" : "next page"
      bordered: true
      foreground: tabs.foreground
      accent: tabs.accent
      fontFamily: tabs.fontFamily
      fontSize: Style.font.caption
      opacity: tabs.loading ? 0.5 : 1

      onClicked: if (!tabs.loading) tabs.nextRequested()
    }
  }
}
