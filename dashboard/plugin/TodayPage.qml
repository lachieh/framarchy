import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model.js" as Model

// Workspace 1 by default: clock, weather, shopping list and room lights.
ColumnLayout {
  id: page
  property Item s
  spacing: Style.spacing.lg

  // Severe weather banner.
  BorderSurface {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.spacing.controlHeight
    visible: s.alerts.length > 0
    radius: Style.cornerRadius
    color: Qt.alpha(s.alertColor, Style.selectedFillAlpha)
    borderSpec: Border.flat(s.alertColor, Math.max(1, Style.space(2)))

    RowLayout {
      anchors { fill: parent; leftMargin: Style.spacing.rowPaddingX; rightMargin: Style.spacing.rowPaddingX }
      spacing: Style.spacing.controlGap
      Glyph { text: Model.ICON.warning; color: s.alertColor }
      PlainText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: s.alerts.length ? s.alerts[0].event + (s.alerts.length > 1 ? "  +" + (s.alerts.length - 1) + " more" : "") + "  ·  " + s.alerts[0].headline : ""
        font.bold: true
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Style.spacing.lg

    // ------------------------------------------------------ clock
    Card {
      Layout.preferredWidth: Style.space(196)
      Layout.fillHeight: true

      Column {
        id: clockColumn
        anchors { left: parent.left; right: parent.right; top: parent.top }

        Row {
          spacing: Style.spacing.sm
          PlainText {
            id: bigTime
            text: Model.formatClock(s.now.getHours(), s.now.getMinutes(), s.config.clock).replace(/[ap]$/, "")
            font { pixelSize: Style.font.display * 2; bold: true }
          }
          PlainText {
            visible: s.config.clock !== "24h"
            anchors.baseline: bigTime.baseline
            text: s.now.getHours() < 12 ? "AM" : "PM"
            dim: true
            font { pixelSize: Style.font.title; bold: true }
          }
        }
        PlainText {
          text: Qt.formatDate(s.now, "dddd")
          color: s.accent
          font { pixelSize: Style.font.heading; bold: true }
        }
        PlainText {
          text: Qt.formatDate(s.now, "d MMMM yyyy")
          dim: true
          font.pixelSize: Style.font.bodySmall
        }
        PlainText {
          visible: s.weather !== null
          topPadding: Style.spacing.sm
          text: s.weather ? "Sun " + s.weather.sunrise + " – " + s.weather.sunset : ""
          dim: true
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: s.otherClocks
          PlainText {
            required property var modelData
            text: modelData.label + "  " + modelData.time + " " + modelData.day
            dim: true
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Home at a glance (each line opens its page), then out-the-door hints:
      // as many whole rows as fit under the clock, glance rows first.
      Column {
        id: details
        anchors { left: parent.left; right: parent.right; top: clockColumn.bottom; bottom: parent.bottom; topMargin: Style.spacing.sm }
        clip: true
        Repeater {
          model: {
            var h = s.home, out = []
            if (h.climate) out.push({ icon: h.climate.action === "heating" ? Model.ICON.fire : Model.ICON.snow,
              lit: h.climate.action === "cooling" || h.climate.action === "heating",
              text: "AC " + (h.climate.mode === "off" ? "off" : h.climate.action + " to " + h.climate.target + "°") + (h.climate.current !== null ? " · " + h.climate.current + "° in" : ""),
              page: "home" })
            if (h.car) out.push({ icon: h.car.charging ? Model.ICON.bolt : Model.ICON.car, lit: h.car.charging,
              text: h.car.name + " " + h.car.battery + "% · " + h.car.chargingText.toLowerCase(), page: "car" })
            var open = h.devices.filter(function(d) { return d.tone === "attention" || d.tone === "alert" })
            out.push({ icon: open.length ? Model.ICON.warning : Model.ICON.check, lit: open.length > 0,
              text: open.length ? open.map(function(d) { return d.name + " " + d.state.toLowerCase() }).join(", ") : "All closed and dry", page: "devices" })
            var advice = s.weather ? Model.advice(s.weather, s.config.units).slice(0, 2) : []
            advice.forEach(function(a) { out.push({ icon: a.icon, lit: true, text: a.text, page: "" }) })
            return out.slice(0, Math.max(0, Math.floor(details.height / Style.spacing.popupRowHeight)))
          }
          Rectangle {
            required property var modelData
            width: parent.width
            height: Style.spacing.popupRowHeight
            radius: Style.cornerRadius
            color: rowTap.pressed ? Style.pressedFill : "transparent"
            Row {
              anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
              spacing: Style.spacing.controlGap
              Glyph { width: Style.font.iconLarge; text: modelData.icon; size: Style.font.iconSmall; color: modelData.lit ? s.accent : s.dim }
              PlainText { width: parent.width - Style.font.iconLarge - parent.spacing; elide: Text.ElideRight; text: modelData.text; font.pixelSize: Style.font.bodySmall }
            }
            MouseArea {
              id: rowTap
              anchors.fill: parent
              enabled: modelData.page !== ""
              onClicked: {
                var spaces = s.config.spaces
                for (var i = 0; i < spaces.length; i++) if (spaces[i].page === modelData.page) s.goToSpace(spaces[i].workspace)
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------ weather
    Card {
      Layout.fillWidth: true
      Layout.fillHeight: true
      title: "Weather" + (s.config.location.name ? " · " + s.config.location.name : "")
      problem: s.weatherError !== ""
      status: s.weatherError !== "" ? s.weatherError + (s.weatherAt ? " · " + Model.ageText(s.weatherAt, s.now.getTime()) : "")
        : Model.ageText(s.weatherAt, s.now.getTime())

      PlainText {
        anchors.centerIn: parent
        visible: s.weather === null
        text: s.weatherError || "Loading forecast…"
        dim: true
      }

      ColumnLayout {
        id: forecast
        anchors.fill: parent
        visible: s.weather !== null
        spacing: Style.spacing.md
        // A rain line only where some column has rain worth noting, to save the height.
        readonly property bool hourlyRain: s.weather !== null && s.weather.hourly.some(function(h, i) { return i % 2 === 1 && h.rain >= 20 })
        readonly property bool dailyRain: s.weather !== null && s.weather.daily.some(function(d) { return d.rain >= 20 })

        RowLayout {
          spacing: Style.spacing.xl
          Glyph { text: s.weather ? s.weather.icon : ""; size: Style.font.display; color: s.accent; Layout.preferredWidth: Style.font.display * 1.3 }
          PlainText {
            text: s.weather ? s.weather.temp + "°" : ""
            font { pixelSize: Style.font.display; bold: true }
          }
          Column {
            Layout.fillWidth: true
            PlainText { width: parent.width; elide: Text.ElideRight; text: s.weather ? s.weather.label : ""; font { pixelSize: Style.font.title; bold: true } }
            PlainText { width: parent.width; elide: Text.ElideRight; text: s.weather ? "Feels " + s.weather.feels + "° · H " + s.weather.hi + "° L " + s.weather.lo + "°" : ""; dim: true; font.pixelSize: Style.font.caption }
            PlainText { width: parent.width; elide: Text.ElideRight; text: s.weather ? "Rain " + s.weather.rainToday + "% · Wind " + s.weather.wind + " " + s.weather.windUnit : ""; dim: true; font.pixelSize: Style.font.caption }
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // Next 12 hours, every second hour.
        RowLayout {
          Layout.fillWidth: true
          spacing: 0
          Repeater {
            model: s.weather ? s.weather.hourly.filter(function(h, i) { return i % 2 === 1 }) : []
            Column {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.spacing.xxs
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; dim: true; font { pixelSize: Style.font.caption; bold: true } }
              Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon }
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp + "°"; font.pixelSize: Style.font.bodySmall }
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; visible: forecast.hourlyRain; text: modelData.rain >= 20 ? modelData.rain + "%" : " "; color: s.accent; font.pixelSize: Style.font.caption }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // Next five days.
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0
          Repeater {
            model: s.weather ? s.weather.daily : []
            Column {
              required property var modelData
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: Style.spacing.xxs
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label.toUpperCase(); dim: true; font { pixelSize: Style.font.caption; bold: true } }
              Glyph { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon }
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.hi + "° " + modelData.lo + "°"; font.pixelSize: Style.font.caption }
              PlainText { anchors.horizontalCenter: parent.horizontalCenter; visible: forecast.dailyRain; text: modelData.rain >= 20 ? modelData.rain + "%" : " "; color: s.accent; font.pixelSize: Style.font.caption }
            }
          }
        }
      }
    }

    // ------------------------------------------------------ shopping list
    Card {
      Layout.preferredWidth: Style.space(156)
      Layout.fillHeight: true
      title: "Shopping"
      problem: s.todoError !== ""
      status: s.todoError !== "" ? s.todoError : s.demo ? "Demo" : s.todoItems.length ? s.todoItems.length + " to get" : ""

      PlainText {
        anchors.fill: parent
        visible: s.todoItems.length === 0
        wrapMode: Text.WordWrap
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: s.todoAt ? "Nothing on the list." : (s.todoError ? "Home Assistant " + s.todoError + "." : "Loading…")
        dim: true
      }

      ListView {
        anchors.fill: parent
        clip: true
        model: s.todoItems
        delegate: Rectangle {
          required property var modelData
          width: ListView.view.width
          height: Style.spacing.controlHeight
          radius: Style.cornerRadius
          color: tap.pressed ? Style.pressedFill : "transparent"
          Row {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: Style.spacing.controlGap
            BorderSurface {
              width: Style.font.body
              height: width
              anchors.verticalCenter: parent.verticalCenter
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.flat(s.accent, Math.max(1, Style.space(1.5)))
            }
            PlainText {
              width: parent.width - Style.font.body - parent.spacing
              elide: Text.ElideRight
              text: modelData.summary
              font.pixelSize: Style.font.bodySmall
            }
          }
          MouseArea { id: tap; anchors.fill: parent; onClicked: s.completeItem(modelData) }
        }
      }
    }
  }

  // -------------------------------------------------------- lights
  Card {
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(80)
    title: "Lights"
    problem: s.haError !== "" || s.configError !== ""
    status: s.configError || s.haStatus

    Flickable {
      anchors.fill: parent
      contentWidth: roomRow.width
      flickableDirection: Flickable.HorizontalFlick
      clip: true

      Row {
        id: roomRow
        height: parent.height
        spacing: Style.spacing.md

        ActionButton {
          height: parent.height
          icon: Model.ICON.power
          label: "All off"
          onActivated: s.allOff()
        }

        Repeater {
          model: s.home.areas
          Toggle {
            required property var modelData
            width: Style.space(164)
            height: parent.height
            label: modelData.name
            description: modelData.on === 0 ? "Off" : modelData.on === modelData.total ? "On" : modelData.on + " of " + modelData.total + " on"
            checked: modelData.on > 0
            titleSize: Style.font.bodySmall
            onClicked: s.toggleRoom(modelData)
          }
        }
      }
    }
  }
}
