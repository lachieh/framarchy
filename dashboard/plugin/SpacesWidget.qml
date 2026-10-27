import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model.js" as Model

// Replaces omarchy.workspaces in the bar: workspaces with a dashboard page
// show its icon (and name when focused); the rest keep their number. As in
// omarchy.workspaces, empty spaces are dimmed; the focused one carries the
// bar's open-panel underline. With no keyboard attached, a close button
// follows the tabs whenever the focused space has a window.
BarWidget {
  id: root
  moduleName: "frame.dashboard"

  property var config: Model.mergeConfig("{}").config

  FileView {
    path: Quickshell.env("HOME") + "/.config/frame-dashboard/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.config = Model.mergeConfig(text()).config
    onFileChanged: reload()
  }

  // 1-5 always, plus any other open workspace up to 10, as omarchy.workspaces does.
  readonly property var ids: {
    var out = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && out.indexOf(id) === -1) out.push(id)
    }
    return out.sort(function(a, b) { return a - b })
  }

  function workspace(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === id) return values[i]
    return null
  }

  // Hyprland.activeToplevel stays null after a shell restart until focus
  // moves, so go by whether the focused space has windows at all.
  readonly property bool spaceHasWindows: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.toplevels.values.length > 0

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground

  implicitWidth: strip.implicitWidth
  implicitHeight: root.barSize

  Row {
    id: strip
    height: root.barSize
    spacing: Style.space(1)

    Repeater {
      model: root.ids
      Item {
        id: tab
        required property int modelData
        readonly property string page: Model.pageFor(root.config, modelData)
        readonly property var ws: root.workspace(modelData)
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0
        width: Math.max(Style.bar.iconSlot, content.implicitWidth + Style.space(12))
        height: strip.height

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: tap.pressed ? Style.pressedFill : "transparent"
        }

        Row {
          id: content
          anchors.centerIn: parent
          spacing: Style.spacing.sm
          opacity: tab.focused || tab.occupied ? 1 : 0.5
          Text {
            visible: tab.page !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: tab.page ? Model.PAGES[tab.page].icon : ""
            color: root.foreground
            font { family: "Font Awesome 7 Free"; weight: Font.Black; pixelSize: Style.bar.iconFont }
          }
          Text {
            visible: tab.page === "" || tab.focused
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: tab.page ? Model.PAGES[tab.page].label : (tab.modelData === 10 ? "0" : String(tab.modelData))
            color: root.foreground
            font { family: root.bar ? root.bar.fontFamily : Style.font.family; pixelSize: Style.font.body }
          }
        }

        // The bar's open-panel mark (Bar.qml openPanelIndicator).
        Rectangle {
          visible: tab.focused
          anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Style.space(2) }
          width: Math.max(Style.space(10), Math.round(parent.width * 0.55))
          height: Style.space(2)
          radius: height / 2
          color: Commons.Color.accent
          opacity: 0.9
        }

        MouseArea {
          id: tap
          anchors.fill: parent
          onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + tab.modelData + "\" })")
        }
      }
    }

    Item {
      visible: root.spaceHasWindows
      width: Style.bar.iconSlot + Style.space(6)
      height: strip.height

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: closeTap.pressed ? Style.pressedFill : "transparent"
      }

      Text {
        anchors.centerIn: parent
        text: Model.ICON.close
        color: root.foreground
        font { family: "Font Awesome 7 Free"; weight: Font.Black; pixelSize: Style.bar.iconFont }
      }

      MouseArea {
        id: closeTap
        anchors.fill: parent
        onClicked: Hyprland.dispatch("hl.dsp.window.close()")
      }
    }
  }
}
