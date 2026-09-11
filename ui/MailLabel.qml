import QtQuick
import qs.Commons

// Keep mail on the shell's monospace font and never interpret mail as markup.
Text {
    font.family: Style.font.family
    font.pixelSize: 12
    color: Color.foreground
    textFormat: Text.PlainText
}
