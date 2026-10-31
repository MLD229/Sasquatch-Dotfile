// QuickToggles.qml — module 8 : pilule unique, 3 icônes empilées.
//   son   → POST /api/system/volume {"mute":bool} via Backend.toggleMute()
//   réseau→ popup réseau (état = Backend.online, lu dans /api/stats)
//   DND   → makoctl mode -t do-not-disturb (mako est le démon de la session)
// État actif : fond accent alpha 0.30 (brief §8).
import QtQuick
import "../qml"

Item {
    id: mod

    // v4 §3 : TROIS cases de Config.caseH (32 px) empilées dans une seule
    // pilule — même hauteur de case que les apps, même rayon que les autres.
    // v5b : en barre HAUTE les trois cases s'alignent en ligne (3 × block),
    // même ordre (son, réseau, DND), une seule pilule.
    implicitHeight: Config.horizontal ? Config.caseH : 3 * Config.caseH
    implicitWidth: Config.horizontal ? (3 * Config.block) : Config.block

    Pill {
        id: bg
        anchors.fill: parent
        // Le survol d'UNE des trois cases remonte le fond de la pilule entière
        // (avant : hovered: false, la pilule ne réagissait jamais).
        hovered: soundArea.containsMouse || netArea.containsMouse
                 || dndArea.containsMouse
    }

    Flow {
        anchors.centerIn: parent
        flow: Config.horizontal ? Flow.LeftToRight : Flow.TopToBottom
        spacing: 0

        // ── Son ───────────────────────────────────────────────────────────
        Item {
            width: Config.block
            height: Config.caseH

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(4, Config.pillRadius - 2)
                color: Backend.muted ? BarPalette.blockActive : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            BarIcon {
                anchors.centerIn: parent
                text: Backend.muted ? "\uf026" : "\uf028"
                size: Config.iconSize
                tint: Backend.muted ? BarPalette.accent : BarPalette.text
            }
            MouseArea {
                id: soundArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
            Tip.hideNow();
            Backend.toggleMute();
        }
                onEntered: {
                    var p = mod.mapToItem(null, 0, 8);
                    Tip.show(Backend.muted ? "Son coupé — clic pour rétablir"
                                           : "Son actif — clic pour couper", p.y);
                }
                onExited: Tip.hide()
            }
        }

        // ── Réseau ────────────────────────────────────────────────────────
        Item {
            width: Config.block
            height: Config.caseH

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(4, Config.pillRadius - 2)
                color: Ui.isOpen("network") ? BarPalette.blockActive : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            BarIcon {
                anchors.centerIn: parent
                text: Backend.online ? "\uf1eb" : "\uf071"
                size: Config.iconSize
                tint: Backend.online ? (Ui.isOpen("network") ? BarPalette.accent : BarPalette.text)
                                     : BarPalette.hot
            }
            MouseArea {
                id: netArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Ui.open("network")
                onEntered: {
                    var p = mod.mapToItem(null, 0, 40);
                    Tip.show(Backend.online
                             ? "Réseau : " + (Backend.netIface || "?") + " — clic pour le détail"
                             : "Réseau indisponible (pas d'interface dans /api/stats)", p.y);
                }
                onExited: Tip.hide()
            }
        }

        // ── Ne pas déranger ──────────────────────────────────────────────
        Item {
            width: Config.block
            height: Config.caseH

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(4, Config.pillRadius - 2)
                color: Backend.dnd ? BarPalette.blockActive : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            BarIcon {
                anchors.centerIn: parent
                text: Backend.dnd ? "\uf1f6" : "\uf0f3"
                size: Config.iconSize
                tint: Backend.dnd ? BarPalette.accent : BarPalette.text
            }
            MouseArea {
                id: dndArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                    Tip.hideNow();
                    if (mouse.button === Qt.RightButton)
                        Ui.open("notifications");
                    else
                        Backend.toggleDnd();
                }
                onEntered: {
                    var p = mod.mapToItem(null, 0, 72);
                    Tip.show(Backend.dnd ? "Ne pas déranger ACTIF (clic : désactiver)"
                                         : "Ne pas déranger inactif (clic : activer)", p.y);
                }
                onExited: Tip.hide()
            }
        }
    }

    // Mesures réelles (tests) : les trois cibles 38 × 38.
    Component.onCompleted: {
        Ui.registerAction("toggle-sound", function () { Backend.toggleMute() });
        Ui.registerAction("toggle-network", function () { Ui.open("network") });
        Ui.registerAction("toggle-dnd", function () { Backend.toggleDnd() });
        Ui.track("toggle-sound", soundArea.parent, soundArea);
        Ui.track("toggle-network", netArea.parent, netArea);
        Ui.track("toggle-dnd", dndArea.parent, dndArea);
    }
    Component.onDestruction: {
        Ui.untrack(soundArea.parent);
        Ui.untrack(netArea.parent);
        Ui.untrack(dndArea.parent);
    }
}
