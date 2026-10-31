// Clock.qml — module 4 : horloge empilée HH / mm / AM-PM + icône calendrier.
// Source : SystemClock (Quickshell) — pas de Timer par module (brief §10.10).
// Clic : CalendarPopup. Infobulle : date longue en japonais + romaji.
import QtQuick
import Quickshell
import "../qml"

Item {
    id: mod

    // v4 §3 : DEUX cases (Config.caseH × 2 = 64 px à 40/4/32). Contenu mesuré :
    // 15 + 15 (HH/mm) + 9 (AM-PM) + 3 (écart) + 12 (icône) = 54 px → 5 px de
    // padding en haut et en bas, donc ≥ 3 px comme les autres blocs.
    // v5b : en barre HAUTE (position top) la même horloge tient sur UNE ligne
    // (« HH:mm » + icône) et ne prend qu'une case de haut. La largeur vient de
    // TextMetrics (jamais une taille en dur).
    implicitHeight: Config.horizontal ? Config.caseH : 2 * Config.caseH
    implicitWidth: Config.horizontal
                   ? (Math.ceil(clockMetrics.advanceWidth) + 10
                      + (Config.calendarIcon ? 16 : 0))
                   : Config.block
    // Chiffres de l'horloge : jamais sous 14 px (brief v2 §4).
    readonly property int digitSize: Math.max(14, Config.clockSize)
    readonly property int periodSize: 9

    readonly property var months: ["janvier", "février", "mars", "avril", "mai", "juin",
                                   "juillet", "août", "septembre", "octobre", "novembre",
                                   "décembre"]
    readonly property var wdKanji: ["日", "月", "火", "水", "木", "金", "土"]
    readonly property var wdRomaji: ["nichiyôbi", "getsuyôbi", "kayôbi", "suiyôbi",
                                     "mokuyôbi", "kin'yôbi", "doyôbi"]

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
        enabled: true
    }

    // Largeur réelle de « HH:mm » à la taille des chiffres (aucune estimation).
    TextMetrics {
        id: clockMetrics
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: mod.digitSize
        font.bold: true
        text: Qt.formatDateTime(sysClock.date, Config.hourFormat + ":" + Config.minuteFormat)
    }

    Pill {
        id: bg
        anchors.fill: parent
        hovered: area.containsMouse
        active: Ui.isOpen("calendar")
    }

    Column {
        visible: !Config.horizontal
        anchors.centerIn: parent
        spacing: 0

        Text {
            width: Config.block
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(sysClock.date, Config.hourFormat)
            color: BarPalette.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: mod.digitSize
            font.bold: true
            renderType: Text.NativeRendering
        }
        Text {
            width: Config.block
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(sysClock.date, Config.minuteFormat)
            color: BarPalette.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: mod.digitSize
            renderType: Text.NativeRendering
        }
        Text {
            width: Config.block
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(sysClock.date, Config.period)
            color: BarPalette.textDim
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: mod.periodSize
            renderType: Text.NativeRendering
        }
        Item { width: 1; height: 3 }
        BarIcon {
            width: Config.block
            height: 12
            visible: Config.calendarIcon
            text: "\uf073"
            size: 11
            tint: BarPalette.textDim
        }
    }

    // Variante « une ligne » (barre haute) : HH:mm + icône calendrier. Même
    // source (SystemClock) et mêmes couleurs que la version empilée.
    Row {
        visible: Config.horizontal
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: clockMetrics.text
            color: BarPalette.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: mod.digitSize
            font.bold: true
            renderType: Text.NativeRendering
        }
        BarIcon {
            visible: Config.calendarIcon
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            text: "\uf073"
            size: 11
            tint: BarPalette.textDim
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Ui.open("calendar")
        onEntered: {
            var d = sysClock.date;
            var p = mod.mapToItem(null, 0, mod.height / 2);
            var t = d.getDate() + " " + mod.months[d.getMonth()] + " " + d.getFullYear()
                    + " — " + mod.wdKanji[d.getDay()] + "曜日 (" + mod.wdRomaji[d.getDay()] + ")";
            Tip.show(t, p.y);
        }
        onExited: Tip.hide()
    }

    // Mesure réelle (tests) : bloc + cible cliquable.
    Component.onCompleted: {
        Ui.track("clock", bg, area);
        Ui.registerAction("clock", function () { Ui.open("calendar") });
    }
    Component.onDestruction: Ui.untrack(bg)
}
