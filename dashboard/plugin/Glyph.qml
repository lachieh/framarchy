import QtQuick
import qs.Commons
import qs.Commons as Commons

// Font Awesome solid icon; codepoints come from model.js ICON.
Text {
  property int size: Style.font.icon
  textFormat: Text.PlainText
  color: Commons.Color.foreground
  font { family: "Font Awesome 7 Free"; weight: Font.Black; pixelSize: size }
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
}
