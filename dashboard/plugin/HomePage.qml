import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model.js" as Model

// Workspace 2 by default: the floor plan, the house AC and the tapped room.
RowLayout {
  id: page
  property Item s
  property string selected: "lounge_room"
  property string floor: s.home.floors.length ? s.home.floors[0].id : ""
  readonly property var floorData: {
    var floors = s.floorplan ? s.floorplan.floors : []
    for (var i = 0; i < floors.length; i++) if (floors[i].id === page.floor) return floors[i]
    return null
  }
  readonly property var room: {
    var rooms = s.home.rooms
    for (var i = 0; i < rooms.length; i++) if (rooms[i].id === page.selected) return rooms[i]
    return null
  }
  readonly property var climate: s.home.climate
  readonly property bool running: climate !== null && (climate.action === "cooling" || climate.action === "heating")
  spacing: Style.spacing.lg

  Card {
    Layout.fillWidth: true
    Layout.fillHeight: true
    title: "Home" + (s.home.averageTemp !== null ? " · " + s.home.averageTemp + "° average" : "")
      + " · " + s.home.areas.filter(function(a) { return a.on > 0 }).length + " rooms lit"
    status: s.haStatus
    problem: s.haError !== ""

    PlainText {
      anchors.centerIn: parent
      visible: page.floorData === null
      width: parent.width * 0.8
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      text: "No floor plan yet. Make ~/.config/frame-dashboard/floorplan.json from UniFi Innerspace with dashboard/tools/floorplan-from-unifi.py."
      dim: true
    }

    FloorPlan {
      anchors.fill: parent
      visible: page.floorData !== null
      s: page.s
      floor: page.floorData
      rooms: s.home.rooms.filter(function(r) { return r.floor === page.floor })
      selected: page.selected
      onRoomTapped: function(room) {
        page.selected = room.id
        if (room.total > 0) s.toggleRoom(room)
      }
    }

    Row {
      anchors { left: parent.left; bottom: parent.bottom }
      spacing: Style.spacing.md
      visible: s.home.floors.length > 1
      Repeater {
        model: s.home.floors
        ActionButton {
          required property var modelData
          label: modelData.name
          selected: page.floor === modelData.id
          onActivated: page.floor = modelData.id
        }
      }
    }
  }

  ColumnLayout {
    Layout.preferredWidth: Style.space(204)
    Layout.fillWidth: false
    Layout.fillHeight: true
    spacing: Style.spacing.lg

    // ---------------------------------------------------- AC
    Card {
      Layout.fillWidth: true
      Layout.preferredHeight: (page.climate ? acColumn.implicitHeight : noClimate.implicitHeight) + chromeHeight
      title: "Air conditioning"
      status: s.haStatus

      PlainText {
        id: noClimate
        anchors.centerIn: parent
        visible: page.climate === null
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        text: "No thermostat found. Set home.climate in config.json to your climate entity."
        dim: true
        font.pixelSize: Style.font.bodySmall
      }

      ColumnLayout {
        id: acColumn
        anchors { left: parent.left; right: parent.right; top: parent.top }
        visible: page.climate !== null
        spacing: Style.spacing.md

        RowLayout {
          spacing: Style.spacing.xl
          Glyph {
            Layout.preferredWidth: Style.font.display
            text: !page.climate ? "" : page.climate.action === "heating" ? Model.ICON.fire : page.climate.action === "off" ? Model.ICON.power
              : page.climate.action === "fan" ? Model.ICON.fan : Model.ICON.snow
            size: Style.font.iconLarge
            color: page.running ? s.accent : s.dim
          }
          PlainText {
            text: page.climate && page.climate.current !== null ? page.climate.current + "°" : "—"
            font { pixelSize: Style.font.display; bold: true }
          }
          Column {
            Layout.fillWidth: true
            PlainText {
              text: !page.climate ? "" : page.climate.mode === "off" ? "Off" : page.climate.action.charAt(0).toUpperCase() + page.climate.action.slice(1)
              color: page.running ? s.accent : s.fg
              font { pixelSize: Style.font.title; bold: true }
            }
            PlainText {
              width: parent.width
              elide: Text.ElideRight
              text: page.climate && page.climate.humidity !== null ? "Inside · " + page.climate.humidity + "%" : "Inside"
              dim: true
              font.pixelSize: Style.font.caption
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md
          enabled: page.climate !== null && page.climate.mode !== "off" && page.climate.target !== null
          opacity: enabled ? 1 : 0.4
          ActionButton {
            icon: Model.ICON.minus
            Layout.preferredWidth: Style.space(36)
            onActivated: s.call("climate/set_temperature", { entity_id: page.climate.entity, temperature: Math.max(page.climate.min, page.climate.target - 1) })
          }
          Column {
            Layout.fillWidth: true
            PlainText {
              anchors.horizontalCenter: parent.horizontalCenter
              text: page.climate && page.climate.target !== null ? page.climate.target + "°" : "—"
              font { pixelSize: Style.font.heading; bold: true }
            }
            PlainText { anchors.horizontalCenter: parent.horizontalCenter; text: "TARGET"; dim: true; font { pixelSize: Style.font.caption; bold: true } }
          }
          ActionButton {
            icon: Model.ICON.plus
            Layout.preferredWidth: Style.space(36)
            onActivated: s.call("climate/set_temperature", { entity_id: page.climate.entity, temperature: Math.min(page.climate.max, page.climate.target + 1) })
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm
          Repeater {
            model: page.climate ? [["off", "Off"], ["cool", "Cool"], ["heat", "Heat"], [page.climate.modes.indexOf("heat_cool") !== -1 ? "heat_cool" : "auto", "Auto"]]
              .filter(function(m) { return page.climate.modes.indexOf(m[0]) !== -1 }) : []
            ActionButton {
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              label: modelData[1]
              selected: page.climate.mode === modelData[0]
              onActivated: s.call("climate/set_hvac_mode", { entity_id: page.climate.entity, hvac_mode: modelData[0] })
            }
          }
        }
      }
    }

    // ---------------------------------------------------- room
    Card {
      Layout.fillWidth: true
      Layout.fillHeight: true
      title: page.room ? page.room.name : "Room"
      status: page.room ? [page.room.temp !== null ? page.room.temp + "°" : "", page.room.humidity !== null ? page.room.humidity + "% humidity" : ""]
        .filter(function(t) { return t }).join(" · ") : ""

      PlainText {
        anchors.centerIn: parent
        visible: page.room === null
        text: "Tap a room on the plan."
        dim: true
      }

      Column {
        anchors.fill: parent
        visible: page.room !== null
        spacing: Style.spacing.md

        Toggle {
          width: parent.width
          enabled: page.room !== null && page.room.total > 0
          opacity: enabled ? 1 : 0.4
          label: "Lights"
          description: !page.room || page.room.total === 0 ? "None in this room"
            : page.room.on === 0 ? "Off" : page.room.on === page.room.total ? "All on" : page.room.on + " of " + page.room.total + " on"
          checked: page.room !== null && page.room.on > 0
          onClicked: if (enabled) s.toggleRoom(page.room)
        }

        Flow {
          id: scenes
          width: parent.width
          spacing: Style.spacing.sm
          visible: page.room !== null && page.room.scene !== null
          // Rows that would run past the card are hidden; layout keeps them so earlier rows don't move.
          readonly property real room: parent.height - y
          Repeater {
            // Hue rooms carry a dozen scenes; offer the everyday ones first.
            model: {
              if (!page.room || !page.room.scene) return []
              var options = page.room.scene.options
              var everyday = ["Bright", "Relax", "Read", "Dimmed", "Nightlight", "Concentrate"].filter(function(o) { return options.indexOf(o) !== -1 })
              return (everyday.length ? everyday : options).slice(0, 6)
            }
            ActionButton {
              required property string modelData
              label: modelData
              readonly property bool fits: y + height <= scenes.room
              opacity: fits ? 1 : 0
              enabled: fits
              selected: page.room.on > 0 && page.room.scene.current === modelData
              onActivated: s.call("select/select_option", { entity_id: page.room.scene.entity, option: modelData })
            }
          }
        }
      }
    }
  }
}
