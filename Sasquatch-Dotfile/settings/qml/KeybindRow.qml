// KeybindRow.qml — une ligne de raccourci : combinaison + section +
// commande éditable + 💾 sauvegarde + ↺ retour à l'originale.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: krow
    property string bindId: ""
    property string mods: ""
    property string key: ""
    property string section: ""
    property string command: ""
    property string originalCommand: ""
    property color accentColor: "#89b4fa"
    property color textColor: "#cdd6f4"
    property color textDimColor: "#a6adc8"
    property color goodColor: "#a6e3a1"
    property color hotColor: "#f38ba8"
    property bool focusActive: false
    signal save(string id, string command)
    signal revert(string id)
    implicitHeight: 34

    RowLayout {
        anchors.fill: parent
        spacing: 8

        ColumnLayout {
            spacing: 0
            Layout.preferredWidth: 112

            Text {
                text: krow.mods ? (krow.mods + " + " + krow.key) : krow.key
                color: krow.textColor
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: krow.section
                color: krow.textDimColor
                font.pixelSize: 9
                elide: Text.ElideRight
                visible: krow.section !== ""
            }
        }

        TextField {
            id: cmdField
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: krow.command
            color: krow.textColor
            font.pixelSize: 12
            font.family: "monospace"
            selectByMouse: true
            padding: 6
            verticalAlignment: Text.AlignVCenter
            selectionColor: Qt.rgba(krow.accentColor.r, krow.accentColor.g, krow.accentColor.b, 0.3)
            onAccepted: krow.save(krow.bindId, cmdField.text)
            onActiveFocusChanged: krow.focusActive = cmdField.activeFocus

            background: Rectangle {
                radius: 8
                color: cmdField.activeFocus ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.width: cmdField.activeFocus ? 1 : 0
                border.color: Qt.rgba(krow.accentColor.r, krow.accentColor.g, krow.accentColor.b, 0.5)
            }
        }

        // 💾 sauvegarder
        Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: saveMa.containsMouse
                   ? Qt.rgba(krow.goodColor.r, krow.goodColor.g, krow.goodColor.b, 0.25)
                   : Qt.rgba(1, 1, 1, 0.06)
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: "💾"
                font.pixelSize: 11
            }
            MouseArea {
                id: saveMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: krow.save(krow.bindId, cmdField.text)
            }
        }

        // ↺ retour à la commande d'origine
        Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: revMa.containsMouse
                   ? Qt.rgba(krow.hotColor.r, krow.hotColor.g, krow.hotColor.b, 0.2)
                   : Qt.rgba(1, 1, 1, 0.06)
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
                anchors.centerIn: parent
                text: "↺"
                color: krow.textDimColor
                font.pixelSize: 12
            }
            MouseArea {
                id: revMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cmdField.text = krow.originalCommand
                    krow.revert(krow.bindId)
                }
            }
        }
    }
}
