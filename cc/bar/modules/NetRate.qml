// NetRate.qml — module 3 : débit réseau ↑/↓.
// Source : Backend.stats.net (déjà calculé par le backend, en Ko/s).
// Clic : popup réseau (iface, IP, débit, historique).
// État d'erreur : backend muet => glyphe + infobulle « indisponible ».
import QtQuick
import "../qml"

Item {
    id: mod

    // v4 §3 : hauteur de case commune (Config.caseH) — jamais plus, jamais moins.
    implicitHeight: Config.caseH
    // Carré dans les deux orientations : une case de Config.block.
    implicitWidth: Config.block
    width: Config.block

    readonly property bool ok: Backend.ttlOk
    // Taille du texte de débit : jamais sous 9 px (brief v2 §4, lisibilité).
    readonly property int netFont: Math.max(9, Config.netSize)

    // Ko/s → texte compact (la colonne fait 40 px : « 1,2M », pas « 1,2 Mo/s »).
    function fmt(v) {
        if (v === undefined || v === null || v < 0)
            return "—";
        var bytes = v * 1024;
        if (v < 1)
            return Math.round(bytes) + "B";
        if (v < 1000)
            return (v < 10 ? String(Math.round(v * 10) / 10).replace(".", ",")
                           : "" + Math.round(v)) + "K";
        return (v / 1024).toFixed(1).replace(".", ",") + "M";
    }
    function fmtFull(v) {
        if (v === undefined || v === null || v < 0)
            return "indisponible";
        var bytes = v * 1024;
        if (v < 1)
            return Math.round(bytes) + " B/s";
        if (v < 1000)
            return (v < 10 ? String(Math.round(v * 10) / 10).replace(".", ",")
                           : "" + Math.round(v)) + " Ko/s";
        return (v / 1024).toFixed(1).replace(".", ",") + " Mo/s";
    }

    Pill {
        id: bg
        anchors.fill: parent
        hovered: area.containsMouse
    }

    // Deux lignes empilées : une Column ne positionne jamais ses enfants par
    // ancres (piège QML) → chaque ligne est un Item pleine largeur et le Text
    // est centré dedans.
    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            // 13 px : 2 × 13 = 26 px dans une case de 32 → 3 px d'air en haut
            // et en bas (v4 §4 : padding ≥ 3 px).
            height: 13
            Text {
                anchors.centerIn: parent
                // Encre mesurée 1,0 px sous le centre de la case (la virgule de
                // « 1,2M » descend sous la ligne de base) : compensation −1 px.
                anchors.verticalCenterOffset: -1
                // v4 §4 : PAS d'espace après la flèche. Mesuré sur
                // JetBrainsMonoNerdFont à 9 px : « ↑ 1,2M » = 32,44 px d'avance
                // pour une case de 32 → débordement ; « ↑1,2M » = 27,03 px
                // (encre 27) → 2,5 px de marge de chaque côté. 5 cellules est
                // le minimum possible en monospace (le « 3 px » demandé
                // exigerait 8 px de police, refusé pour la lisibilité).
                text: mod.ok ? ("↑" + mod.fmt(Backend.netUp)) : "—"
                color: mod.ok ? BarPalette.text : BarPalette.warn
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: mod.netFont
                renderType: Text.NativeRendering
            }
        }
        Item {
            width: parent.width
            height: 13
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: mod.ok ? ("↓" + mod.fmt(Backend.netDown)) : "—"
                color: mod.ok ? BarPalette.text : BarPalette.warn
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: mod.netFont
                renderType: Text.NativeRendering
            }
        }
    }

    // État d'erreur explicite : petit point d'alerte en coin.
    Rectangle {
        visible: !mod.ok
        width: 4
        height: 4
        radius: 2
        color: BarPalette.warn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 2
        anchors.topMargin: 2
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Ui.open("network")
        onEntered: {
            var p = mod.mapToItem(null, 0, mod.height / 2);
            var t = mod.ok
                ? "↑ " + mod.fmtFull(Backend.netUp) + "  ↓ " + mod.fmtFull(Backend.netDown)
                  + (Backend.netIface ? "  (" + Backend.netIface + ")" : "")
                : "Réseau indisponible (backend CC 8765)";
            Tip.show(t, p.y);
        }
        onExited: Tip.hide()
    }

    // Mesure réelle (tests) : bloc + cible cliquable.
    Component.onCompleted: {
        Ui.track("netRate", bg, area);
        Ui.registerAction("netRate", function () { Ui.open("network") });
    }
    Component.onDestruction: Ui.untrack(bg)
}
