// VolumePopup.qml — popup volume + luminosité (module Volume).
// Écritures : POST /api/system/volume {"v":N|"mute":bool} et
// POST /api/system/brightness {"v":N}, uniquement via Backend.
import QtQuick
import Quickshell
import Quickshell.Wayland
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
    implicitWidth: 286
    implicitHeight: 250
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("volume")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-volume"

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

    Component.onCompleted: {
        Backend.pollVolume();
        Backend.pollBrightness();
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
            spacing: 14

            // ── En-tête ───────────────────────────────────────────────────
            Row {
                width: parent.width
                height: Config.hitMin
                Text {
                    width: parent.width - Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sortie · volume système"
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
                HitButton {
                    name: "volume-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    onClicked: Ui.close()
                }
            }

            // ── Volume ────────────────────────────────────────────────────
            Row {
                width: parent.width
                height: 26
                spacing: 10

                Item {
                    width: 22
                    height: 26
                    BarIcon {
                        anchors.centerIn: parent
                        text: Backend.muted ? "\uf026" : "\uf028"
                        size: 15
                        tint: Backend.muted ? BarPalette.hot : BarPalette.text
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Backend.toggleMute()
                    }
                }

                Item {
                    id: volTrack
                    width: parent.width - 22 - 10 - 40
                    height: 26

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: BarPalette.a(BarPalette.text, 0.16)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * (Backend.volPct / 100.0)
                        height: 6
                        radius: 3
                        color: Backend.muted ? BarPalette.textDim : BarPalette.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    Rectangle {
                        x: Math.max(0, Math.min(volTrack.width - 10,
                                                 volTrack.width * (Backend.volPct / 100.0) - 5))
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: BarPalette.text
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPositionChanged: function (mouse) {
                            if (pressed)
                                Backend.setVolume(100 * Math.max(0, Math.min(1, mouse.x / width)));
                        }
                        onPressed: function (mouse) {
                            Backend.setVolume(100 * Math.max(0, Math.min(1, mouse.x / width)));
                        }
                    }
                }

                Text {
                    width: 40
                    height: 26
                    text: Backend.volOk ? Backend.volPct + " %" : "—"
                    color: Backend.volOk ? BarPalette.text : BarPalette.warn
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: BarPalette.a(BarPalette.text, 0.10)
            }

            // ── Luminosité ────────────────────────────────────────────────
            Row {
                width: parent.width
                height: 26
                spacing: 10

                Item {
                    width: 22
                    height: 26
                    BarIcon {
                        anchors.centerIn: parent
                        text: "\uf0eb"
                        size: 15
                        tint: BarPalette.text
                    }
                }

                Item {
                    id: brightTrack
                    width: parent.width - 22 - 10 - 40
                    height: 26

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: BarPalette.a(BarPalette.text, 0.16)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * (Math.max(0, Backend.brightness) / 100.0)
                        height: 6
                        radius: 3
                        color: BarPalette.warn
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPositionChanged: function (mouse) {
                            if (pressed)
                                Backend.setBrightness(100 * Math.max(0, Math.min(1, mouse.x / width)));
                        }
                        onPressed: function (mouse) {
                            Backend.setBrightness(100 * Math.max(0, Math.min(1, mouse.x / width)));
                        }
                    }
                }

                Text {
                    width: 40
                    height: 26
                    text: Backend.brightOk ? Backend.brightness + " %" : "—"
                    color: Backend.brightOk ? BarPalette.text : BarPalette.warn
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                width: parent.width
                text: Backend.volOk ? "wpctl · source unique = backend CC"
                                    : "Backend volume indisponible (127.0.0.1:8765)"
                color: Backend.volOk ? BarPalette.textDim : BarPalette.warn
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }
}
