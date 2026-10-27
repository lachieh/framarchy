import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Touch button with the states of Omarchy's bordered Button: theme fills for
// pressed and selected, the selected border when the theme has one. With
// `confirm`, it acts only after a 0.9 s hold, so a brush against the screen
// can't unlock a door or open the garage.
BorderSurface {
  id: button
  property string label: ""
  property string icon: ""
  property bool confirm: false
  property bool selected: false
  property real progress: 0
  signal activated()

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  implicitWidth: Math.max(Style.spacing.controlHeight, content.implicitWidth + Style.spacing.controlPaddingX * 2)
  implicitHeight: Style.spacing.controlHeight
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.4
  color: area.pressed ? Style.pressedFillFor(fg, accent) : selected ? Style.selectedFillFor(fg, accent) : Style.normalFillFor(fg, accent)
  borderSpec: selected && Border.controlHasWidth("selected") ? Border.controlSpec("selected", fg, accent) : Border.controlSpec("normal", fg, accent)
  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  Rectangle {
    visible: button.confirm && button.progress > 0
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    width: parent.width * button.progress
    radius: parent.radius
    color: Style.selectionFillFor(button.fg, button.accent)
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.spacing.controlGap
    Glyph { visible: button.icon !== ""; text: button.icon; color: button.selected ? button.accent : button.fg; anchors.verticalCenter: parent.verticalCenter }
    Text {
      visible: button.label !== ""
      textFormat: Text.PlainText
      text: button.confirm && area.pressed ? "Hold…" : button.label
      color: button.fg
      font { family: Style.font.family; pixelSize: Style.font.body; bold: button.selected }
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  NumberAnimation {
    id: hold
    target: button
    property: "progress"
    from: 0
    to: 1
    duration: 900
    onFinished: {
      button.progress = 0
      if (area.pressed) button.activated()
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: button.enabled
    preventStealing: button.confirm
    onPressed: if (button.confirm) hold.restart()
    onReleased: if (button.confirm) { hold.stop(); button.progress = 0 }
    onCanceled: { hold.stop(); button.progress = 0 }
    onClicked: if (!button.confirm) button.activated()
  }
}
