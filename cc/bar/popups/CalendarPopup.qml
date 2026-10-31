// CalendarPopup.qml — popup calendrier (module Clock).
// Surface dédiée (PanelWindow, exclusiveZone 0) : la barre ne grandit jamais.
// Mois courant + navigation ±1 mois ; aujourd'hui cerclé d'accent.
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
    implicitWidth: 276
    implicitHeight: 330
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("calendar")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-calendar"

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

    property int monthOffset: 0
    readonly property var months: ["janvier", "février", "mars", "avril", "mai", "juin",
                                   "juillet", "août", "septembre", "octobre", "novembre",
                                   "décembre"]
    readonly property var wdShort: ["L", "M", "M", "J", "V", "S", "D"]

    SystemClock { id: sys; precision: SystemClock.Minutes }

    function monthStart(off) {
        return new Date(sys.date.getFullYear(), sys.date.getMonth() + off, 1);
    }
    readonly property int firstWeekday: (win.monthStart(win.monthOffset).getDay() + 6) % 7
    readonly property int daysInMonth: {
        var d = win.monthStart(win.monthOffset);
        return new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    }
    readonly property bool sameMonth: win.monthOffset === 0

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
                spacing: 0

                Text {
                    width: parent.width - 3 * Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.months[win.monthStart(win.monthOffset).getMonth()]
                          + " " + win.monthStart(win.monthOffset).getFullYear()
                    color: BarPalette.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                HitButton {
                    name: "calendrier-prev"
                    glyph: "\uf060"
                    glyphSize: 12
                    hoverColor: BarPalette.accent
                    tipText: "Mois précédent"
                    onClicked: win.monthOffset -= 1
                }
                HitButton {
                    name: "calendrier-next"
                    glyph: "\uf061"
                    glyphSize: 12
                    hoverColor: BarPalette.accent
                    tipText: "Mois suivant"
                    onClicked: win.monthOffset += 1
                }
                HitButton {
                    name: "calendrier-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer (Échap plus tard)"
                    onClicked: Ui.close()
                }
            }

            // En-tête des jours (semaine commençant lundi)
            Grid {
                columns: 7
                columnSpacing: 1
                width: parent.width
                Repeater {
                    model: win.wdShort
                    delegate: Text {
                        required property var modelData
                        width: 35
                        height: 18
                        text: modelData
                        color: BarPalette.textDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Grid {
                columns: 7
                columnSpacing: 1
                rowSpacing: 1
                width: parent.width

                Repeater {
                    model: 42

                    delegate: Item {
                        id: cell
                        required property int index

                        readonly property int dayNum: cell.index - win.firstWeekday + 1
                        readonly property bool valid: cell.dayNum >= 1 && cell.dayNum <= win.daysInMonth
                        readonly property bool today: cell.valid && win.sameMonth
                                                      && cell.dayNum === sys.date.getDate()

                        width: 35
                        height: 30

                        Rectangle {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            color: cell.today ? BarPalette.a(BarPalette.accent, 0.25) : "transparent"
                            border.width: cell.today ? 1 : 0
                            border.color: BarPalette.accent
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.valid ? "" + cell.dayNum : ""
                            color: cell.today ? BarPalette.accent
                                              : (cell.valid ? BarPalette.text : "transparent")
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Aujourd'hui : " + Qt.formatDateTime(sys.date, "dddd dd MMMM yyyy")
                color: BarPalette.textDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
    }
}
