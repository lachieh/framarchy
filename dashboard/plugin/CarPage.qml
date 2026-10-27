import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model.js" as Model

// Workspace 3 by default: the Tesla, through Home Assistant's Tesla Fleet or
// Teslemetry integration (entity names in home.js CAR_ENTITIES).
RowLayout {
  id: page
  property Item s
  readonly property var car: s.home.car
  spacing: Style.spacing.lg

  Card {
    Layout.fillWidth: true
    Layout.fillHeight: true
    title: page.car ? page.car.name : "Car"
    status: s.haStatus

    PlainText {
      anchors.centerIn: parent
      visible: page.car === null
      width: parent.width * 0.8
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
      text: "No car found. Add the Tesla Fleet integration in Home Assistant, then set home.car.prefix in config.json to the vehicle's entity prefix."
      dim: true
    }

    ColumnLayout {
      anchors.fill: parent
      visible: page.car !== null
      spacing: Style.spacing.md

      // Where it is and whether it's secure; anything to look at is selected.
      Row {
        spacing: Style.spacing.md
        Repeater {
          model: page.car ? [
            { icon: Model.ICON.location, text: page.car.location, flag: false },
            { icon: page.car.locked ? Model.ICON.lock : Model.ICON.lockOpen, text: page.car.locked ? "Locked" : "Unlocked", flag: !page.car.locked },
            { icon: Model.ICON.shield, text: page.car.sentry ? "Sentry on" : "Sentry off", flag: page.car.sentry }
          ] : []
          BorderSurface {
            required property var modelData
            width: chip.implicitWidth + Style.spacing.controlPaddingX * 2
            height: chip.implicitHeight + Style.spacing.controlPaddingY * 2
            radius: Style.cornerRadius
            color: modelData.flag ? Style.selectedFillFor(s.fg, s.accent) : Style.normalFillFor(s.fg, s.accent)
            borderSpec: Border.controlSpec(modelData.flag && Border.controlHasWidth("selected") ? "selected" : "normal", s.fg, s.accent)
            Row {
              id: chip
              anchors.centerIn: parent
              spacing: Style.spacing.sm
              Glyph { text: modelData.icon; size: Style.font.iconSmall; color: modelData.flag ? s.accent : s.fg; anchors.verticalCenter: parent.verticalCenter }
              PlainText { text: modelData.text; font { pixelSize: Style.font.caption; bold: modelData.flag } anchors.verticalCenter: parent.verticalCenter }
            }
          }
        }
      }

      // Side profile of a crossover, plugged in on the left like a Model Y.
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Item {
          id: profile
          width: 360
          height: 120
          anchors.centerIn: parent
          scale: Math.min(1.5, (parent.width - 120) / 360, parent.height / 140)

          Rectangle {
            visible: page.car !== null && page.car.plugged
            x: -32
            y: 58
            width: 44
            height: 4
            radius: 2
            color: page.car && page.car.charging ? s.accent : Qt.alpha(s.fg, 0.4)
            SequentialAnimation on opacity {
              running: page.car !== null && page.car.charging && page.visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.35; duration: 900 }
              NumberAnimation { to: 1; duration: 900 }
            }
          }

          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: Qt.alpha(s.fg, 0.1)
              strokeColor: Qt.alpha(s.fg, 0.55)
              strokeWidth: 2
              joinStyle: ShapePath.RoundJoin
              PathSvg { path: "M 10 94 L 10 70 Q 12 56 34 52 L 92 44 Q 126 12 180 8 L 246 8 Q 286 10 316 40 L 340 48 Q 354 54 354 72 L 354 94 Z" }
            }
            ShapePath {
              fillColor: Qt.alpha(s.fg, 0.18)
              strokeColor: "transparent"
              PathSvg { path: "M 104 44 Q 136 18 180 15 L 204 15 L 204 44 Z M 212 15 L 244 15 Q 278 17 304 42 L 212 44 Z" }
            }
          }

          Repeater {
            model: [76, 286]
            Rectangle {
              required property int modelData
              x: modelData - 24
              y: 66
              width: 52
              height: 52
              radius: 26
              color: s.bg
              border.width: 3
              border.color: Qt.alpha(s.fg, 0.55)
              Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: Qt.alpha(s.fg, 0.35) }
            }
          }
        }
      }

      // Battery, with the charge limit marked.
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xl
        PlainText {
          text: page.car ? page.car.battery + "%" : ""
          font { pixelSize: Style.font.display; bold: true }
        }
        Column {
          Layout.fillWidth: true
          PlainText {
            text: page.car && page.car.range !== null ? page.car.range + " " + page.car.rangeUnit + " range" : ""
            font { pixelSize: Style.font.title; bold: true }
          }
          PlainText {
            width: parent.width
            elide: Text.ElideRight
            text: !page.car ? "" : [page.car.chargingText,
              page.car.charging && page.car.chargerPower !== null ? page.car.chargerPower + " kW" : "",
              page.car.timeToFull ? page.car.timeToFull + " to " + page.car.limit + "%" : ""].filter(function(t) { return t }).join(" · ")
            color: page.car && page.car.charging ? s.accent : s.dim
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(10)
        radius: Style.cornerRadius
        color: Style.normalFill
        border.width: Style.normalBorderWidth
        border.color: Style.normalBorderColor
        Rectangle {
          width: page.car ? parent.width * page.car.battery / 100 : 0
          height: parent.height
          radius: Style.cornerRadius
          color: page.car && page.car.battery < 20 && !page.car.charging ? s.alertColor : s.accent
        }
        Rectangle {
          visible: page.car !== null && page.car.limit !== null
          x: page.car ? parent.width * page.car.limit / 100 - 1 : 0
          y: -3
          width: 2
          height: parent.height + 6
          color: s.fg
        }
      }
    }
  }

  // ------------------------------------------------------ controls
  Card {
    Layout.preferredWidth: Style.space(220)
    Layout.fillHeight: true
    title: "Controls"
    visible: page.car !== null

    Column {
      anchors.fill: parent
      spacing: Style.spacing.lg

      Repeater {
        model: !page.car ? [] : [
          { icon: page.car.locked ? Model.ICON.lock : Model.ICON.lockOpen, name: "Doors", state: page.car.locked ? "Locked" : "Unlocked",
            label: page.car.locked ? "Unlock" : "Lock", confirm: page.car.locked,
            service: page.car.locked ? "lock/unlock" : "lock/lock", entity: page.car.entities.lock },
          { icon: Model.ICON.fan, name: "Climate", state: (page.car.climateOn ? "On" : "Off") + (page.car.inside !== null ? " · " + page.car.inside + "° in" : "") + (page.car.outside !== null ? ", " + page.car.outside + "° out" : ""),
            label: page.car.climateOn ? "Turn off" : "Precondition",
            service: page.car.climateOn ? "climate/turn_off" : "climate/turn_on", entity: page.car.entities.climate },
          { icon: Model.ICON.plug, name: "Charge port", state: page.car.portOpen ? "Open" : "Closed",
            label: page.car.portOpen ? "Close" : "Open",
            service: page.car.portOpen ? "cover/close_cover" : "cover/open_cover", entity: page.car.entities.chargePort },
          { icon: Model.ICON.shield, name: "Sentry mode", state: page.car.sentry ? "On" : "Off",
            label: page.car.sentry ? "Turn off" : "Turn on",
            service: page.car.sentry ? "switch/turn_off" : "switch/turn_on", entity: page.car.entities.sentry }
        ]
        RowLayout {
          required property var modelData
          width: parent.width
          spacing: Style.spacing.lg
          Glyph { Layout.preferredWidth: Style.font.iconLarge; text: modelData.icon; color: s.dim }
          Column {
            Layout.fillWidth: true
            PlainText { width: parent.width; elide: Text.ElideRight; text: modelData.name; font { pixelSize: Style.font.bodySmall; bold: true } }
            PlainText { width: parent.width; elide: Text.ElideRight; text: modelData.state; dim: true; font.pixelSize: Style.font.caption }
          }
          ActionButton {
            Layout.preferredWidth: Style.space(84)
            label: modelData.label
            confirm: modelData.confirm === true
            onActivated: s.call(modelData.service, { entity_id: modelData.entity })
          }
        }
      }

      PlainText {
        visible: page.car !== null && page.car.odometer !== null
        text: page.car ? Math.round(page.car.odometer).toLocaleString(Qt.locale("en_US"), "f", 0) + " " + page.car.rangeUnit + " on the clock" : ""
        dim: true
        font.pixelSize: Style.font.caption
      }
    }
  }
}
