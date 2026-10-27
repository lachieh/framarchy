import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model.js" as Model

// Workspace 4 by default: appliances, doors and sensors as one status grid.
ColumnLayout {
  id: page
  property Item s
  readonly property var attention: s.home.devices.filter(function(d) { return d.tone === "attention" || d.tone === "alert" })
  spacing: Style.spacing.lg

  function iconFor(d) {
    switch (d.kind) {
    case "washer": return Model.ICON.jacket
    case "dryer": return Model.ICON.wind
    case "dishwasher": return Model.ICON.utensils
    case "fridge": return Model.ICON.tempLow
    case "lock": return d.state === "Locked" ? Model.ICON.lock : Model.ICON.lockOpen
    case "garage": return Model.ICON.garage
    case "door": return d.state === "Open" ? Model.ICON.doorOpen : Model.ICON.doorClosed
    case "leak": return Model.ICON.droplet
    case "vacuum": return Model.ICON.broom
    }
    return Model.ICON.plug
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    Glyph { text: page.attention.length ? Model.ICON.warning : Model.ICON.check; size: Style.font.iconLarge; color: page.attention.length ? s.accent : s.dim }
    PlainText {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: page.attention.length ? page.attention.length + (page.attention.length === 1 ? " thing needs" : " things need") + " a look: "
        + page.attention.map(function(d) { return d.name.toLowerCase() + " " + d.state.toLowerCase() }).join(", ")
        : "Everything is closed, dry and quiet."
      font { pixelSize: Style.font.title; bold: true }
    }
    PlainText { text: s.haStatus; color: s.haError ? s.alertColor : Qt.darker(s.fg, 1.4); font { pixelSize: Style.font.caption; bold: true } }
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    columns: 3
    rowSpacing: Style.spacing.lg
    columnSpacing: Style.spacing.lg

    // A tile is a panel; one that needs a look is drawn selected, or urgent
    // for an alert.
    Repeater {
      model: s.home.devices
      BorderSurface {
        id: tile
        required property var modelData
        readonly property bool ok: modelData.tone === "ok"
        readonly property color toneColor: s.toneColor(modelData.tone)
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 1
        radius: Style.cornerRadius
        color: ok ? Commons.Color.popups.background : Qt.alpha(toneColor, Style.selectedFillAlpha)
        borderSpec: ok ? Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border, Commons.Color.popups.border, Math.max(1, Style.space(2)))
          : Border.flat(toneColor, Math.max(1, Style.space(2)))
        padding: Style.space(10)
        opacity: modelData.missing ? 0.45 : 1

        Glyph {
          anchors { left: parent.left; top: parent.top; leftMargin: tile.contentLeftInset; topMargin: tile.contentTopInset }
          text: page.iconFor(modelData)
          size: Style.font.iconLarge
          color: tile.ok ? s.dim : tile.toneColor
        }

        Column {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: tile.contentLeftInset; rightMargin: tile.contentRightInset; bottomMargin: tile.contentBottomInset }
          PlainText { width: parent.width; elide: Text.ElideRight; text: modelData.name.toUpperCase(); color: Qt.darker(s.fg, 1.4); font { pixelSize: Style.font.caption; bold: true } }
          PlainText {
            width: parent.width
            elide: Text.ElideRight
            text: modelData.state
            color: tile.ok ? s.fg : tile.toneColor
            font { pixelSize: Style.font.heading; bold: true }
          }
          PlainText {
            width: parent.width
            elide: Text.ElideRight
            text: modelData.detail || " "
            dim: true
            font.pixelSize: Style.font.caption
          }
        }

        ActionButton {
          visible: modelData.action !== null
          anchors { right: parent.right; top: parent.top; rightMargin: tile.contentRightInset; topMargin: tile.contentTopInset }
          label: modelData.action ? modelData.action.label : ""
          confirm: modelData.action !== null && modelData.action.confirm === true
          onActivated: s.call(modelData.action.service, modelData.action.data)
        }
      }
    }
  }
}
