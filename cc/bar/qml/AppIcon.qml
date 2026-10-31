// AppIcon.qml — icône d'application (bloc de Config.block), avec pastille de
// comptage optionnelle et état « ouverte » VISIBLE (brief v3 §4).
//
// Brief §10.9 : une image ne détermine JAMAIS la taille → width/height fixes et
// fillMode PreserveAspectFit (une icône ne doit pas être rognée).
//
// ÉTAT ACTIF (v3) : un fond blockActive à 0.34 se confondait avec le panneau à
// 0.24. Trois marques cumulées, donc lisibles même sans comparer deux alphas :
//   1. barre d'accent latérale (3 × 22 px) ;
//   2. halo d'accent derrière l'icône (accentSoft) ;
//   3. pilule en blockActive + contour d'accent (voir Pill.qml).
// La molette n'est PLUS gérée ici : chaque module pose une seule zone de
// molette sur tout son bloc (qml/WheelZone.qml) — un geste, une action.
import QtQuick
import "."

Item {
    id: root

    property string name: ""                  // identifiant pour Ui.dumpRects()
    property string iconPath: ""
    property string label: ""
    property int windows: 0
    property bool open: windows > 0
    property bool hovered: area.containsMouse
    property bool active: false
    property string tipText: ""
    property bool enabledItem: true

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    // Molette : relancée au module, qui la traite (un seul gestionnaire pour
    // tout le bloc — voir WheelZone.qml). L'icône ne décide rien elle-même.
    signal scrolled(int delta)

    // Brief v2 §4/§2 : bloc recalculé depuis bar.json, jamais une taille en dur.
    implicitWidth: Config.block
    implicitHeight: Config.block

    Pill {
        anchors.fill: parent
        // v4 §3 : rayon commun (Config.pillRadius), comme toutes les pilules.
        hovered: root.hovered
        active: root.active
    }

    // 1. Barre d'accent latérale (le repère le plus lisible en colonne).
    Rectangle {
        visible: root.active
        width: 3
        height: Math.round(parent.height * 0.58)
        radius: 1.5
        x: 1
        anchors.verticalCenter: parent.verticalCenter
        color: BarPalette.accentBar
        Behavior on height { NumberAnimation { duration: 140 } }
    }

    // 2. Halo derrière l'icône.
    Rectangle {
        visible: root.active
        anchors.centerIn: parent
        width: Config.appIconSize + 6
        height: Config.appIconSize + 6
        radius: 8
        color: BarPalette.accentSoft
    }

    Image {
        id: img
        width: Config.appIconSize
        height: Config.appIconSize
        anchors.centerIn: parent
        source: root.iconPath.length > 0 ? "file://" + root.iconPath : ""
        sourceSize.width: Config.appIconSize * 2
        sourceSize.height: Config.appIconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        visible: status === Image.Ready
        opacity: root.enabledItem ? 1.0 : 0.4
    }

    // Pas d'icône résolue : pastille avec l'initiale de l'app (jamais un carré
    // vide ni un glyphe « inconnu »). Lisible et différenciant pour les classes
    // sans .desktop (jeux Wine : plariumplay.exe, raid.exe…).
    Rectangle {
        anchors.centerIn: parent
        width: Config.appIconSize
        height: Config.appIconSize
        radius: 6
        visible: img.status !== Image.Ready
        color: BarPalette.accentSoft
        opacity: root.enabledItem ? 0.9 : 0.4

        Text {
            anchors.centerIn: parent
            text: {
                var s = ("" + root.label).trim();
                return s.length > 0 ? s.charAt(0).toUpperCase() : "•";
            }
            color: BarPalette.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.bold: true
            renderType: Text.NativeRendering
        }
    }

    // v4 §4 : la pastille reste DANS le bloc (marges 1 px, plus de -3 px qui
    // la faisait sortir de la colonne de 40 px).
    Badge {
        count: root.windows
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 1
        anchors.topMargin: 1
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            // v4 §8 : l'infobulle disparaît au clic.
            Tip.hideNow();
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
            else
                root.clicked();
        }
        onWheel: function (wheel) {
            var d = wheel.angleDelta.y > 0 ? 1 : (wheel.angleDelta.y < 0 ? -1 : 0);
            if (d !== 0) {
                wheel.accepted = true;
                root.scrolled(d);
            }
        }
        onEntered: if (root.tipText.length > 0) {
            var p = root.mapToItem(null, 0, root.height / 2);
            Tip.show(root.tipText, p.y);
        }
        onExited: Tip.hide()
    }

    // Mesure réelle (tests) : rectangle visuel + rectangle cliquable.
    Component.onCompleted: if (root.name.length > 0) Ui.track(root.name, root, area)
    Component.onDestruction: Ui.untrack(root)
}
