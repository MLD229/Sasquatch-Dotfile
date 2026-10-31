// NotificationsPopup.qml — popup notifications.
// mako reste LE démon de notifications de la session : la barre ne déclare pas
// de NotificationServer (deux démons se disputeraient org.freedesktop.Notifications).
// On lit donc l'historique mako en JSON (`makoctl history -j`), à l'ouverture.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../qml"

PanelWindow {
    id: win

    // v5b : la popup s'ouvre du côté de la barre (gauche / droite) et SOUS
    // elle quand la barre est en haut — sinon elle s'ouvrirait à l'opposé.
    anchors {
        left: !Config.sideRight
        right: Config.sideRight
        top: true
    }
    // Les surfaces layer sont placées DANS la zone réservée par la barre :
    // la marge part donc du bord intérieur de cette zone, pas du bord de
    // l'écran. popupGap = l'écart visuel voulu après la barre (10 px).
    // Config.popupTop place la popup SOUS la barre quand elle est en haut.
    margins {
        left: Config.sideRight ? 0 : Config.popupGap
        right: Config.sideRight ? Config.popupGap : 0
        top: Config.popupTop
    }
    implicitWidth: 330
    implicitHeight: 338
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("notifications")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-notifications"

    // v4 §7 : Échap ferme la popup, et un SEUL popup est ouvert à la fois
    // (Ui.popup est un nom unique : ouvrir ailleurs ferme celui-ci).
    // Le focus clavier est « à la demande » (OnDemand) : la surface le reçoit
    // quand elle est affichée/cliquée. Ce n'est PAS un grab : aucun raccourci
    // du compositeur n'est capturé, hyprlock n'est pas concerné.
    focusable: true
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: Ui.close()
    }

    BackgroundEffect.blurRegion: Region { item: card; radius: 16 }

    property var items: []
    property string err: ""

    function parse(txt) {
        var d = null;
        try {
            d = JSON.parse(txt);
        } catch (e) {
            win.err = "makoctl : JSON invalide";
            return [];
        }
        if (!Array.isArray(d)) {
            win.err = "makoctl : réponse inattendue";
            return [];
        }
        win.err = "";
        return d;
    }

    Process {
        id: histProc
        command: ["makoctl", "history", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var arr = win.parse(this.text || "");
                win.items = arr.slice(0, 8);
            }
        }
    }

    Process {
        id: clearProc
        command: ["makoctl", "dismiss", "-a"]
        onRunningChanged: if (!running) histProc.running = true
    }

    onVisibleChanged: {
        if (visible) {
            histProc.running = false;
            histProc.running = true;
            Backend.pollDnd();
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: BarPalette.a(BarPalette.bgSolid, 0.94)
        border.width: 1
        border.color: BarPalette.border

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            Row {
                width: parent.width
                height: Config.hitMin
                Text {
                    width: parent.width - 2 * Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications" + (Backend.dnd ? " · DND actif" : "")
                    color: Backend.dnd ? BarPalette.warn : BarPalette.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
                HitButton {
                    name: "notifs-clear"
                    glyph: "\uf1f8"   // corbeille : effacer l'historique
                    glyphSize: 11
                    tipText: "Effacer l'historique (makoctl dismiss -a)"
                    onClicked: clearProc.running = true
                }
                HitButton {
                    name: "notifs-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    onClicked: Ui.close()
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 70
                clip: true
                spacing: 8
                model: win.items
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property var modelData

                    width: ListView.view ? ListView.view.width : 0
                    height: Math.max(44, bodyCol.implicitHeight + 14)

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: BarPalette.a(BarPalette.text, 0.05)
                    }
                    Column {
                        id: bodyCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2
                        Text {
                            width: parent.width
                            text: (row.modelData.summary || "(sans titre)")
                            color: BarPalette.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: (row.modelData.body || "")
                            color: BarPalette.textDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: (row.modelData.app_name || "?")
                            color: BarPalette.a(BarPalette.textDim, 0.7)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: win.items.length === 0
                text: win.err.length > 0 ? win.err : "aucune notification dans l'historique"
                color: win.err.length > 0 ? BarPalette.warn : BarPalette.textDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }
}
