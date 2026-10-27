import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A titled panel, drawn as Omarchy draws its own: the popup surface and border,
// the theme's corners, and a section header. `status` is a short line in the
// header for staleness or errors, so a card never goes blank without saying why.
BorderSurface {
  id: card
  property string title: ""
  property string status: ""
  property bool problem: false
  default property alias content: body.data
  // Header, padding and border: add the content's height for a card that fits it.
  readonly property real chromeHeight: body.anchors.topMargin + body.anchors.bottomMargin

  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Math.max(1, Style.space(2)))
  padding: Style.space(10)

  PanelSectionHeader {
    id: heading
    visible: card.title !== ""
    anchors { left: parent.left; top: parent.top; leftMargin: card.contentLeftInset; topMargin: card.contentTopInset - topPadding }
    width: Math.min(implicitWidth, card.width - card.contentLeftInset - card.contentRightInset - (statusText.visible ? statusText.implicitWidth + Style.spacing.lg : 0))
    elide: Text.ElideRight
    text: card.title.toUpperCase()
  }
  Text {
    id: statusText
    visible: card.status !== ""
    anchors { right: parent.right; baseline: heading.baseline; rightMargin: card.contentRightInset }
    width: Math.min(implicitWidth, card.width * 0.6)
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: card.status
    color: card.problem ? Commons.Color.urgent : Qt.darker(Commons.Color.foreground, 1.4)
    font { family: Style.font.family; pixelSize: Style.font.caption; bold: true }
  }
  Item {
    id: body
    anchors {
      fill: parent
      leftMargin: card.contentLeftInset; rightMargin: card.contentRightInset; bottomMargin: card.contentBottomInset
      topMargin: card.title !== "" ? heading.y + heading.height + Style.spacing.lg : card.contentTopInset
    }
  }
}
