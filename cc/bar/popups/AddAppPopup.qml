// AddAppPopup.qml — « Ajouter une application » (bouton « + » de AppDock).
// Brief v3 §3 : champ de recherche + liste des applications INSTALLÉES
// (source appindex.py --json, déjà chargé dans AppIndex), chaque ligne avec son
// icône. Un clic écrit bar.json (barjson.py, atomique) et referme la popup ;
// la barre se recharge à chaud par le FileView de Config.
//
// Une app déjà épinglée n'est pas dupliquée : barjson.py la réactive
// (enabled: true) et la popup le signale (« épinglée »).
//
// Focus clavier : WlrKeyboardFocus.OnDemand, c'est-à-dire le focus seulement
// tant que la popup est affichée — ce n'est PAS un grab global (aucun raccourci
// n'est capturé, le bureau reste utilisable, hyprlock n'est pas concerné).
import QtQuick
import QtQuick.Layouts
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
    // Les surfaces layer vivent DANS la zone réservée par la barre :
    // popupGap = 10 px après elle (config, pas une valeur en dur ici).
    margins {
        left: Config.sideRight ? 0 : Config.popupGap
        right: Config.sideRight ? Config.popupGap : 0
        top: Config.popupTop
    }
    implicitWidth: 340
    implicitHeight: 470
    exclusiveZone: 0
    color: "transparent"
    visible: Ui.isOpen("addapp")
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sasquatch-bar-addapp"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // v4 §7 : Échap ferme même si le focus a quitté le champ de recherche
    // (le TextInput a son propre Keys.onEscapePressed, celui-ci est le filet).
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: Ui.close()
    }

    BackgroundEffect.blurRegion: Region { item: card; radius: 16 }

    property var rows: []
    property string query: ""

    readonly property var filtered: {
        var q = win.query.trim().toLowerCase();
        var out = [];
        for (var i = 0; i < win.rows.length; i++) {
            var r = win.rows[i];
            if (q.length === 0
                || ("" + r.name).toLowerCase().indexOf(q) >= 0
                || ("" + r.id).toLowerCase().indexOf(q) >= 0)
                out.push(r);
        }
        return out;
    }

    function isPinnedId(id) {
        var apps = Config.apps;
        var k = Hypr.norm(id);
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i];
            if (!a || a.enabled === false)
                continue;
            if (Hypr.norm(a.id) === k || Hypr.norm(a.desktop) === k)
                return true;
        }
        return false;
    }

    function collect() {
        var out = [];
        var apps = AppIndex.apps || ({});
        for (var id in apps) {
            var a = apps[id];
            if (!a)
                continue;
            out.push({
                id: id,
                name: a.name || id,
                icon: a.icon || "",
                cls: a.class || id,
                // Appli « système » (NoDisplay/Hidden) : épinglable, mais
                // marquée « sys » pour ne pas la confondre avec une app de menu.
                system: a.system === true,
                pinned: win.isPinnedId(id)
            });
        }
        // Tri : applis de menu d'abord (ordre alphabétique), puis applis
        // « système » — sinon les 100 modules KDE noient les vraies applis.
        out.sort(function (x, y) {
            if (!!x.system !== !!y.system)
                return x.system ? 1 : -1;
            var a1 = ("" + x.name).toLowerCase();
            var b1 = ("" + y.name).toLowerCase();
            return a1 < b1 ? -1 : (a1 > b1 ? 1 : 0);
        });
        return out;
    }

    function refresh() {
        win.rows = win.collect();
    }

    onVisibleChanged: {
        if (visible) {
            win.query = "";
            win.refresh();
            searchField.forceActiveFocus();
        } else {
            searchField.focus = false;
        }
    }
    Component.onCompleted: win.refresh()
    // L'index peut arriver après la première ouverture (Process appindex.py).
    Connections {
        target: AppIndex
        function onAppsChanged() { win.refresh() }
    }

    function add(id) {
        PinWriter.pin(id);
        Ui.close();
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: BarPalette.a(BarPalette.bgSolid, 0.94)
        border.width: 1
        border.color: BarPalette.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.hitMin

                Text {
                    Layout.fillWidth: true
                    text: "Ajouter une application"
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                HitButton {
                    name: "addapp-close"
                    glyph: "\uf00d"
                    glyphSize: 11
                    tipText: "Fermer"
                    onClicked: Ui.close()
                }
            }

            // Champ de recherche
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.hitMin
                radius: 10
                color: BarPalette.a(BarPalette.card, Config.cardAlpha)
                border.width: 1
                border.color: searchField.activeFocus ? BarPalette.borderHover : BarPalette.border

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    visible: searchField.text.length === 0
                    text: "Rechercher…"
                    color: BarPalette.textDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }

                TextInput {
                    id: searchField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: BarPalette.text
                    selectionColor: BarPalette.accentBar
                    selectedTextColor: BarPalette.bgSolid
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    clip: true
                    focus: true
                    onTextChanged: win.query = text
                    Keys.onEscapePressed: Ui.close()
                    Keys.onReturnPressed: {
                        if (win.filtered.length > 0)
                            win.add(win.filtered[0].id);
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: win.filtered
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
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            source: row.modelData.icon.length > 0
                                    ? "file://" + row.modelData.icon : ""
                            sourceSize.width: 36
                            sourceSize.height: 36
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                        Text {
                            width: parent.width - 46 - (row.modelData.system ? 26 : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.name
                            color: row.modelData.system ? BarPalette.textDim : BarPalette.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        // Marqueur des applis « système » (NoDisplay) : elles
                        // étaient invisibles du sélecteur avant la v3.1.
                        Text {
                            visible: row.modelData.system
                            anchors.verticalCenter: parent.verticalCenter
                            text: "sys"
                            color: BarPalette.textDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                        }
                        // Déjà épinglée : un point d'accent (pas de glyphe, la
                        // coche Nerd Font n'a pas de métriques de texte).
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.pinned
                            width: 6
                            height: 6
                            radius: 3
                            color: BarPalette.accentBar
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.add(row.modelData.id)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.filtered.length === 0
                text: AppIndex.ready ? "aucune application ne correspond"
                                      : "index des applications en cours de lecture…"
                color: BarPalette.textDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
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
