// WindowsPopup.qml — menu des fenêtres d'une classe (clic droit AppDock /
// RunningApps) et liste de débordement du module RunningApps.
// Clic sur une entrée : focus de la fenêtre + fermeture de la popup.
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
    implicitWidth: 330
    implicitHeight: Math.min(440, 68 + Math.max(1, win.rows.length) * 38)
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("windows")
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-windows"

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

    property var rows: []

    function collect() {
        var out = [];
        var list = Hypr.toplevels.values || [];
        var want = Hypr.norm(Ui.windowClass);
        for (var i = 0; i < list.length; i++) {
            var c = Hypr.classOf(list[i]);
            if (want.length > 0 && Hypr.norm(c) !== want)
                continue;
            out.push({
                cls: c,
                title: Hypr.titleOf(list[i]),
                addr: Hypr.addressOf(list[i])
            });
        }
        return out;
    }

    onVisibleChanged: if (visible) win.rows = win.collect()
    Component.onCompleted: win.rows = win.collect()

    // Suit l'ouverture/fermeture de fenêtres pendant que la popup est visible.
    Connections {
        target: Hypr.toplevels
        function onValuesChanged() {
            if (win.visible)
                win.rows = win.collect();
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
            spacing: 6

            Row {
                width: parent.width
                height: Config.hitMin
                Text {
                    width: parent.width - Config.hitMin
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Ui.windowTitle.length > 0 ? Ui.windowTitle : "Fenêtres")
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                HitButton {
                    name: "fenetres-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    onClicked: Ui.close()
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 44
                clip: true
                spacing: 4
                model: win.rows
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property var modelData

                    width: ListView.view ? ListView.view.width : 0
                    height: Config.hitMin

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: rowArea.containsMouse ? BarPalette.rowHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8
                        Image {
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            source: {
                                var p = AppIndex.iconFor(row.modelData.cls);
                                return p.length > 0 ? "file://" + p : "";
                            }
                            sourceSize.width: 32
                            sourceSize.height: 32
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Text {
                            width: parent.width - 30
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.title.length > 0
                                  ? row.modelData.title : row.modelData.cls
                            color: BarPalette.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Hypr.focusWindow(row.modelData.addr);
                            Ui.close();
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: win.rows.length === 0
                text: "aucune fenêtre"
                color: BarPalette.textDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }
}
