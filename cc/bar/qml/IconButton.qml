// IconButton.qml — cible cliquable carrée de Config.hit px (= Config.block,
// 32 px à une barre de 40), glyphe centré dedans. Brief v2 §2 : la zone
// cliquable couvre EXACTEMENT la zone visuelle (même rectangle, pas de
// décalage au survol). v4 §4 : la cible ne dépasse JAMAIS la colonne.
// Événements : clicked(), rightClicked(), scrolled(int) — molette reçue même
// sans survol explicite si hoverEnabled est vrai.
import QtQuick
import "."

Item {
    id: btn

    property string name: ""                  // identifiant pour Ui.dumpRects()
    property string glyph: ""
    property int glyphSize: Config.iconSize
    property bool active: false
    property bool dimmed: false               // état « indisponible »
    property bool clickable: true
    property string tipText: ""
    property color glyphColor: BarPalette.text
    property color activeGlyphColor: BarPalette.accent
    // v4 §3 : rayon commun à toutes les pilules (Config.pillRadius).
    property int radiusDefault: Config.pillRadius
    property bool flatWhenIdle: true

    signal clicked()
    signal rightClicked()
    signal scrolled(int delta)

    implicitWidth: Config.hit
    implicitHeight: Config.hit

    Pill {
        anchors.fill: parent
        radiusDefault: btn.radiusDefault
        flat: btn.flatWhenIdle
        hovered: area.containsMouse
        active: btn.active
    }

    BarIcon {
        anchors.centerIn: parent
        text: btn.glyph
        size: btn.glyphSize
        opacity: btn.dimmed ? 0.45 : 1.0
        tint: btn.active ? btn.activeGlyphColor : btn.glyphColor
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.clickable
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            // v4 §8 : un clic fait disparaître l'infobulle (elle ne survit pas
            // à l'action qu'elle décrit).
            Tip.hideNow();
            if (mouse.button === Qt.RightButton)
                btn.rightClicked();
            else
                btn.clicked();
        }
        onWheel: function (wheel) {
            var d = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0);
            if (d !== 0 && btn.clickable)
                btn.scrolled(d);
        }
        onEntered: if (btn.tipText.length > 0) {
            var p = btn.mapToItem(null, 0, btn.height / 2);
            Tip.show(btn.tipText, p.y);
        }
        onExited: Tip.hide()
    }

    // Mesure réelle (tests) : rectangle visuel + rectangle cliquable.
    Component.onCompleted: if (btn.name.length > 0) Ui.track(btn.name, btn, area)
    Component.onDestruction: Ui.untrack(btn)
}
