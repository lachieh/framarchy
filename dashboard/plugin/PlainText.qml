import QtQuick
import qs.Commons
import qs.Commons as Commons

// Text in the theme's font and type scale. Always plain: names and states come
// from Home Assistant and the network, and AutoText would render markup in
// them. `dim` is Omarchy's secondary text colour.
Text {
  property bool dim: false
  textFormat: Text.PlainText
  color: dim ? Qt.darker(Commons.Color.foreground, 1.5) : Commons.Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
}
