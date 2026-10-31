// AppMenuPopup.qml — menu d'une application de la barre (clic droit).
//
// Brief v3 §3 : « clic droit sur une app épinglée → petite entrée Détacher »,
// « clic droit sur une app en cours → Épingler ». Les deux passent par la même
// surface, qui garde aussi l'accès à la liste des fenêtres (l'ancien clic
// droit, désormais au clic milieu).
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../qml"

PanelWindow {
    id: menu

    // v5b : la popup s'ouvre du côté de la barre (gauche / droite) et SOUS
    // elle quand la barre est en haut — sinon elle s'ouvrirait à l'opposé.
    anchors {
        left: !Config.sideRight
        right: Config.sideRight
        top: true
    }
    margins {
        left: Config.sideRight ? 0 : Config.popupGap
        right: Config.sideRight ? Config.popupGap : 0
        top: Config.popupTop
    }
    implicitWidth: 260
    implicitHeight: 152 + (PinWriter.lastError.length > 0 ? 26 : 0)
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("appmenu")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-appmenu"

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

    readonly property bool isPinned: Ui.appMenuKind === "pinned"
    readonly property string title: Ui.appMenuTitle.length > 0 ? Ui.appMenuTitle : "Application"
    // Épingler exige un id .desktop : une classe sans .desktop ne peut pas
    // entrer dans bar.json (le menu le dit au lieu d'écrire une entrée morte).
    readonly property bool canPin: Ui.appMenuId.length > 0

    function act(kind) {
        if (kind === "windows") {
            Ui.openWindows(Ui.appMenuClass, Ui.appMenuTitle);
            return;
        }
        if (kind === "pin") {
            if (!menu.canPin) {
                Hypr.miss("aucun .desktop pour « " + Ui.appMenuClass + " » : épinglage impossible");
                return;
            }
            PinWriter.pin(Ui.appMenuId);
            Ui.close();
            return;
        }
        if (kind === "unpin") {
            PinWriter.unpin(Ui.appMenuId);
            Ui.close();
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
            anchors.margins: 12
            spacing: 4

            Item {
                width: parent.width
                height: Config.hitMin

                Text {
                    width: parent.width - Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.title
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                HitButton {
                    name: "appmenu-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    anchors.right: parent.right
                    onClicked: Ui.close()
                }
            }

            // ── Épingler / Détacher ──────────────────────────────────────
            Item {
                width: parent.width
                height: Config.hitMin

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: pinArea.containsMouse && (menu.isPinned || menu.canPin)
                           ? BarPalette.rowHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                BarIcon {
                    id: pinGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.isPinned ? "\uf1f8" : "\u002b"
                    size: 12
                    tint: (menu.isPinned || menu.canPin) ? BarPalette.text : BarPalette.textDim
                }
                Text {
                    anchors.left: pinGlyph.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: menu.isPinned ? "Détacher de la barre"
                                        : (menu.canPin ? "Épingler dans la barre"
                                                       : "Épingler (pas de .desktop)")
                    color: (menu.isPinned || menu.canPin) ? BarPalette.text : BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
                MouseArea {
                    id: pinArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: (menu.isPinned || menu.canPin) ? Qt.PointingHandCursor
                                                                : Qt.ArrowCursor
                    onClicked: menu.act(menu.isPinned ? "unpin" : "pin")
                }
            }

            // ── Fenêtres ─────────────────────────────────────────────────
            Item {
                width: parent.width
                height: Config.hitMin

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: winArea.containsMouse ? BarPalette.rowHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                BarIcon {
                    id: winGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf2d0"
                    size: 12
                    tint: BarPalette.text
                }
                Text {
                    anchors.left: winGlyph.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Fenêtres"
                    color: BarPalette.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
                MouseArea {
                    id: winArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.act("windows")
                }
            }

            Text {
                width: parent.width
                visible: PinWriter.lastError.length > 0
                text: PinWriter.lastError
                color: BarPalette.hot
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }
        }
    }
}
