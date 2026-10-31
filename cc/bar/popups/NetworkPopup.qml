// NetworkPopup.qml — popup réseau (module NetRate / QuickToggles).
// Données : Backend.stats (iface, débits) + `ip -4 addr` pour l'adresse IP
// (lue à l'ouverture seulement : aucune sonde permanente).
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
    implicitWidth: 300
    implicitHeight: 264
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("network")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-network"

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

    property string ipText: ""

    function fmt(v) {
        if (v === undefined || v === null || v < 0)
            return "—";
        var bytes = v * 1024;
        if (v < 1) return Math.round(bytes) + " B/s";
        if (v < 1000) return (Math.round(v * 10) / 10).toString().replace(".", ",") + " Ko/s";
        return (v / 1024).toFixed(1).replace(".", ",") + " Mo/s";
    }

    Process {
        id: ipProc
        command: ["ip", "-4", "-o", "addr", "show", "dev", Backend.netIface]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = (this.text || "").match(/inet\s+([0-9.]+)/);
                win.ipText = m ? m[1] : "";
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            ipProc.running = false;
            ipProc.running = true;
            Backend.pollStats();
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
            anchors.margins: 16
            spacing: 12

            Row {
                width: parent.width
                height: Config.hitMin
                Text {
                    width: parent.width - Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: Backend.online ? "Réseau · " + Backend.netIface
                                         : "Réseau — aucune interface"
                    color: Backend.online ? BarPalette.text : BarPalette.warn
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
                HitButton {
                    name: "reseau-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    onClicked: Ui.close()
                }
            }

            Row {
                width: parent.width
                spacing: 8
                Text {
                    text: "IP"
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    width: 30
                }
                Text {
                    text: win.ipText.length > 0 ? win.ipText : (Backend.online ? "…" : "—")
                    color: BarPalette.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }

            Row {
                width: parent.width
                spacing: 16
                Column {
                    spacing: 2
                    Text {
                        text: "↑ " + win.fmt(Backend.netUp)
                        color: BarPalette.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    Text {
                        text: "envoi"
                        color: BarPalette.textDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }
                Column {
                    spacing: 2
                    Text {
                        text: "↓ " + win.fmt(Backend.netDown)
                        color: BarPalette.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    Text {
                        text: "réception"
                        color: BarPalette.textDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }
            }

            // Historique : 30 échantillons (Backend.netHistory, 1 par tick 2 s).
            Item {
                width: parent.width
                height: 56

                Row {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: Backend.netHistory.slice(-30)

                        delegate: Rectangle {
                            id: bar
                            required property var modelData
                            required property int index

                            readonly property real maxVal: {
                                var h = Backend.netHistory.slice(-30);
                                var m = 1;
                                for (var i = 0; i < h.length; i++) {
                                    if (h[i] > m) m = h[i];
                                }
                                return m;
                            }

                            width: Math.max(2, (parent.width - 29 * 2) / 30)
                            height: Math.max(1, 54 * Math.min(1, bar.modelData / bar.maxVal))
                            radius: 1
                            color: BarPalette.a(BarPalette.accent, 0.75)
                        }
                    }
                }
                Text {
                    visible: Backend.netHistory.length === 0
                    anchors.centerIn: parent
                    text: "pas d'historique"
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
            }

            Text {
                width: parent.width
                text: Backend.ttlOk ? "source : /api/stats (backend CC, 2 s)"
                                    : "backend CC indisponible — 127.0.0.1:8765"
                color: Backend.ttlOk ? BarPalette.textDim : BarPalette.warn
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }
}
