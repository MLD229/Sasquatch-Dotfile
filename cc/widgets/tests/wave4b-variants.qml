// wave4b-variants.qml — preuve des 4 widgets de la dernière vague
// (notifications, workspaces, apps, notes) + des deux correctifs de la vague
// (libellés compacts des toggles, message vide unique de la playlist).
//
// Jamais le CC plein écran (brief §9.1) : PanelWindow 1180 × 620, layer Top,
// exclusiveZone 0, capture self-grab (grabToImage), assertions en console.
//
// Lancement :
//   QML_IMPORT_PATH=$HOME/.config/cc/widgets \
//   SASQUATCH_WAVE4B_GRAB=/tmp/wave4b.png \
//   timeout 22 quickshell -p cc/widgets/tests/wave4b-variants.qml
//
// Capture 1 : données RÉELLES (mako history, Hyprland, favoris de bar.json,
// notes du serveur). Capture 2 : état « mako absent » injecté DANS LE HARNAIS
// seulement, pour prouver l'état « indisponible + commande d'installation ».
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    PanelWindow {
        id: win

        implicitWidth: 1180
        implicitHeight: 620

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-wave4b-variants"
        WlrLayershell.exclusiveZone: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
        }
        margins {
            top: 40
            left: 40
        }

        readonly property string grabPath: {
            var v = Quickshell.env("SASQUATCH_WAVE4B_GRAB");
            return (typeof v === "string") ? v : "";
        }

        // Une variante = un Loader sur le composant du REGISTRE (le chemin ne
        // vient jamais d'ailleurs, brief §4).
        component Variant: Loader {
            id: v

            property string widgetType: ""
            property string varName: "normal"
            property var styleObj: ({ alpha: 0.24, accent: "auto", blur: 9, radius: 16 })
            property var opts: ({})

            source: WidgetRegistry.component(v.widgetType)

            onLoaded: {
                v.item.instanceId = "w4b-" + v.widgetType + "-" + v.varName;
                v.item.host = "cc";
                v.item.variant = v.varName;
                v.item.editing = false;
                v.item.style = v.styleObj;
                v.item.options = v.opts;
            }
        }

        Item {
            id: board
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusPanel
                color: Theme.a(Theme.bgSolid, 1.0)
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacing
                spacing: 8

                Text {
                    width: parent.width
                    text: "vague 4b — notifications · workspaces · apps · notes"
                          + " · serveur " + (Api.online ? "en ligne" : "muet")
                          + " · mako " + (Notifs.available ? "présent" : "absent")
                          + " (" + Notifs.count + " notif.)"
                          + " · favoris " + Apps.favorites.length
                          + " · notes " + Notes.count
                    color: Theme.inkDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                // ── rangée 1 : les trois cartes normal ────────────────────
                Row {
                    spacing: 10

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "notifications"
                        varName: "normal"
                        opts: ({ maxItems: 3, showBadge: true })
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "workspaces"
                        varName: "normal"
                        opts: ({ count: 10, showCount: true })
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "notes"
                        varName: "normal"
                        opts: ({ maxNotes: 4 })
                    }
                }

                // ── rangée 2 : favoris normal + playlist (correctif vide) ──
                Row {
                    spacing: 10

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "apps"
                        varName: "normal"
                        opts: ({ maxItems: 6, showNames: true })
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "playlist"
                        varName: "normal"
                        opts: ({ maxTracks: 5, showArtist: true })
                    }
                }

                // ── rangée 3 : compact (dont le correctif libellés) ───────
                Row {
                    spacing: 10

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "notifications"
                        varName: "compact"
                    }

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "workspaces"
                        varName: "compact"
                    }

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "apps"
                        varName: "compact"
                    }

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "toggles"
                        varName: "compact"
                    }
                }
            }
        }

        // ── Assertions console ───────────────────────────────────────────
        function dumpRegistry() {
            var ids = ["notifications", "workspaces", "apps", "notes"];
            for (var i = 0; i < ids.length; ++i) {
                var id = ids[i];
                console.log("CHECK registre " + id + " : dispo=" + WidgetRegistry.isAvailable(id)
                            + " variantes=" + WidgetRegistry.variantNames(id).join(",")
                            + " défaut=" + WidgetRegistry.variantOrDefault(id)
                            + " hôtes=" + WidgetRegistry.hosts(id).join(","));
            }
        }

        function dumpState() {
            console.log("CHECK notifs : polls=" + Notifs.polls + " disponible=" + Notifs.available
                        + " ok=" + Notifs.ok + " total=" + Notifs.count
                        + " visibles=" + Notifs.activeCount
                        + " première=" + JSON.stringify(Notifs.items.length > 0
                                                        ? (Notifs.items[0].app + " · " + Notifs.items[0].summary)
                                                        : "")
                        + " install=" + (Notifs.available ? "-" : Notifs.install));
            console.log("CHECK workspaces : bureaux signalés=" + wsProbe.liveCount
                        + " actif=" + wsProbe.focusedId
                        + " fenêtres totales=" + wsProbe.total
                        + " détail=" + JSON.stringify(wsProbe.counts));
            console.log("CHECK apps : index=" + Apps.ready + " favoris=" + Apps.favorites.length
                        + " premier=" + JSON.stringify(Apps.favorites.length > 0
                                                       ? (Apps.favorites[0].id + " / "
                                                          + Apps.favorites[0].name + " / icône="
                                                          + (Apps.favorites[0].icon.length > 0 ? "oui" : "non"))
                                                       : "")
                        + " erreur=" + (Apps.lastError.length > 0 ? Apps.lastError : "-"));
            console.log("CHECK notes : polls=" + Notes.polls + " ok=" + Notes.ok
                        + " total=" + Notes.count
                        + " première=" + JSON.stringify(Notes.items.length > 0
                                                        ? Notes.items[0].text : "")
                        + " fichier=" + Notes.file);
            console.log("CHECK playlist : mpdOk=" + Playlist.mpdOk
                        + " pistes=" + Playlist.count
                        + " déclarées=" + Playlist.declaredCount
                        + " → message vide unique (en-tête et pied vides)");
        }

        // Sonde : mêmes données et même arithmétique que WorkspacesWidget
        // (assertions seulement ; le widget, lui, est chargé par le registre).
        Item {
            id: wsProbe
            visible: false

            readonly property var values: {
                var m = Hyprland.workspaces;
                return (m && m.values) ? m.values : [];
            }
            readonly property int liveCount: wsProbe.values.length
            readonly property int focusedId: {
                for (var i = 0; i < wsProbe.values.length; ++i) {
                    if (wsProbe.values[i] && wsProbe.values[i].focused === true)
                        return wsProbe.values[i].id;
                }
                return -1;
            }
            readonly property var counts: {
                var out = ({});
                var m = Hyprland.toplevels;
                var tops = (m && m.values) ? m.values : [];
                for (var i = 0; i < tops.length; ++i) {
                    var o = tops[i] ? tops[i].lastIpcObject : null;
                    if (o && o.workspace && typeof o.workspace.id === "number")
                        out["" + o.workspace.id] = (out["" + o.workspace.id] || 0) + 1;
                }
                return out;
            }
            readonly property int total: {
                var n = 0;
                for (var k in wsProbe.counts)
                    n += wsProbe.counts[k];
                return n;
            }
        }

        Timer {
            interval: 2600
            running: true
            repeat: false
            onTriggered: {
                win.dumpRegistry();
                win.dumpState();
                if (win.grabPath.length > 0) {
                    board.grabToImage(function (res) {
                        console.log("wave4b-variants: capture 1 (données réelles) =",
                                    res.saveToFile(win.grabPath));
                    });
                }
            }
        }

        // ── Capture 2 : mako absent (état injecté, harnais seulement) ─────
        Timer {
            interval: 3600
            running: true
            repeat: false
            onTriggered: {
                Notifs.pollTimer.running = false;
                Notifs.items = [];
                Notifs.count = 0;
                Notifs.activeCount = 0;
                Notifs.available = false;
                Notifs.running = false;
                Notifs.ok = false;
                Notifs.polls = 1;
                Notifs.lastError = "mako n'est pas installé";
                Notifs.install = "sudo pacman -S mako";
                console.log("CHECK simulation mako absent : disponible=" + Notifs.available
                            + " install=" + Notifs.install);
            }
        }

        Timer {
            interval: 4400
            running: true
            repeat: false
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                var path2 = win.grabPath.replace(/\.png$/, "-missing.png");
                board.grabToImage(function (res) {
                    console.log("wave4b-variants: capture 2 (mako absent) =", res.saveToFile(path2));
                });
            }
        }
    }
}
