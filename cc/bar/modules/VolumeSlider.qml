// VolumeSlider.qml — module 5 : slider vertical en pointillés (12 tirets).
// Source unique de vérité : Backend.volume (GET /api/system/volume), POST {"v":N}.
// Molette : ±5 %. Clic : VolumePopup (sortie, mute, luminosité).
// Muet : les tirets s'effacent et une icône mute s'affiche (brief §8).
import QtQuick
import "../qml"

Item {
    id: mod

    // v4 §3/§4 : 10 tirets (5 px + 4 px d'écart = 86 px de colonne) dans TROIS
    // cases (3 × Config.caseH = 96 px) → 5 px de padding, et une hauteur qui
    // reste un multiple de la case comme l'horloge (2) et les toggles (3).
    // v5b : en barre HAUTE les tirets s'alignent en ligne (5 px de large), le
    // module tient dans UNE case et se remplit de gauche à droite.
    readonly property int dashes: 10
    readonly property int dashGap: 4
    readonly property real level: Backend.volOk ? Backend.volPct / 100.0 : 0
    readonly property int filled: Math.round(mod.level * mod.dashes)

    implicitHeight: Config.horizontal ? Config.caseH : 3 * Config.caseH
    implicitWidth: Config.horizontal
                   ? (mod.dashes * 5 + (mod.dashes - 1) * mod.dashGap)
                   : Config.block

    Pill {
        id: bg
        anchors.fill: parent
        hovered: area.containsMouse
        active: Ui.isOpen("volume")
    }

    Flow {
        id: ticks
        anchors.centerIn: parent
        flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
        spacing: mod.dashGap
        visible: !Backend.muted

        Repeater {
            model: mod.dashes

            delegate: Rectangle {
                id: dash
                required property int index

                // Remplissage : du bas vers le haut en colonne (index 0 = tiret
                // du haut), de gauche à droite en ligne (index 0 = gauche).
                readonly property bool on: Config.horizontal
                                           ? (dash.index + 1) <= mod.filled
                                           : (mod.dashes - dash.index) <= mod.filled

                width: Config.horizontal ? 5 : 12
                height: Config.horizontal ? 12 : 5
                radius: 2.5
                color: dash.on ? BarPalette.accent : BarPalette.a(BarPalette.text, 0.18)
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
    }

    // État muet : icône explicite, pas de barre vide ambiguë.
    BarIcon {
        anchors.centerIn: parent
        visible: Backend.muted
        text: "\uf026"
        size: 18
        tint: BarPalette.textDim
    }

    // Backend muet (volume non lu) : point d'alerte.
    Rectangle {
        visible: !Backend.volOk
        width: 4
        height: 4
        radius: 2
        color: BarPalette.warn
        anchors.top: parent.top
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: Ui.open("volume")
        onWheel: function (wheel) {
            var d = wheel.angleDelta.y > 0 ? 5 : (wheel.angleDelta.y < 0 ? -5 : 0);
            if (d !== 0)
                Backend.nudgeVolume(d);
        }
        onEntered: {
            var p = mod.mapToItem(null, 0, mod.height / 2);
            Tip.show(Backend.volOk
                     ? "Volume " + Backend.volPct + " %" + (Backend.muted ? " (muet)" : "")
                       + " — molette ±5 %"
                     : "Volume indisponible (backend CC 8765)", p.y);
        }
        onExited: Tip.hide()
    }

    // Mesure réelle (tests) : bloc + cible cliquable (molette comprise).
    // La zone de molette EST cette cible : elle couvre tout le bloc.
    Component.onCompleted: {
        Ui.track("volume", bg, area);
        Ui.trackWheel("volume", area);
        Ui.registerAction("volume", function () { Ui.open("volume") });
        Ui.registerAction("volume-up", function () { Backend.nudgeVolume(5) });
        Ui.registerAction("volume-down", function () { Backend.nudgeVolume(-5) });
    }
    Component.onDestruction: {
        Ui.untrack(bg);
        Ui.untrackWheel(area);
    }
}
