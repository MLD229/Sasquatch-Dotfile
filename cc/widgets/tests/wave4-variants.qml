// wave4-variants.qml — preuve des 4 widgets de la vague finale (playlist,
// calendar, connectivity, toggles) : variantes côte à côte, assertions dans la
// console et capture self-grab. Jamais le CC plein écran (brief §9.1).
//
// Lancement :
//   QML_IMPORT_PATH=$HOME/.config/cc/widgets \
//   SASQUATCH_WAVE4_GRAB=/tmp/wave4-variants.png \
//   timeout 20 quickshell -p cc/widgets/tests/wave4-variants.qml
//
// Deux captures : la première avec les DONNÉES RÉELLES (file MPD + tâches du
// serveur), la seconde après injection — dans le harnais seulement — d'une
// piste marquée `current` et de tâches datées, pour prouver le rendu de la
// piste courante et le placement des points sur la grille du mois.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    PanelWindow {
        id: win

        implicitWidth: 1180
        implicitHeight: 720

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-wave4-variants"
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
            var v = Quickshell.env("SASQUATCH_WAVE4_GRAB");
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
                v.item.instanceId = "w4-" + v.widgetType + "-" + v.varName;
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
                spacing: 10

                Text {
                    width: parent.width
                    text: "vague finale — playlist · calendar · connectivity · toggles"
                          + " · serveur " + (Api.online ? "en ligne" : "muet")
                          + " · MPD " + (Playlist.mpdOk ? "ok (" + Playlist.count + " pistes)" : "injoignable")
                    color: Theme.inkDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                // ── rangée 1 : les deux hero ──────────────────────────────
                Row {
                    spacing: 10

                    Variant {
                        width: 560
                        height: 260
                        widgetType: "calendar"
                        varName: "hero"
                        styleObj: ({ alpha: 0.09, accent: "auto", blur: 9, radius: 16 })
                        opts: ({ showList: true })
                    }

                    Variant {
                        width: 560
                        height: 260
                        widgetType: "playlist"
                        varName: "hero"
                        styleObj: ({ alpha: 0.09, accent: "auto", blur: 9, radius: 16 })
                        opts: ({ maxTracks: 8, showArtist: true })
                    }
                }

                // ── rangée 2 : normal ─────────────────────────────────────
                Row {
                    spacing: 10

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "playlist"
                        varName: "normal"
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "calendar"
                        varName: "normal"
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "connectivity"
                        varName: "normal"
                    }
                }

                // ── rangée 3 : compact + normal ───────────────────────────
                Row {
                    spacing: 10

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "connectivity"
                        varName: "compact"
                    }

                    Variant {
                        width: 220
                        height: 64
                        widgetType: "toggles"
                        varName: "compact"
                    }

                    Variant {
                        width: 360
                        height: 180
                        widgetType: "toggles"
                        varName: "normal"
                    }
                }
            }
        }

        // ── Assertions : registre + état réel des singletons ──────────────
        function dumpRegistry() {
            var ids = ["playlist", "calendar", "connectivity", "toggles"];
            for (var i = 0; i < ids.length; ++i) {
                var id = ids[i];
                var ok = WidgetRegistry.isAvailable(id);
                var names = WidgetRegistry.variantNames(id).join(",");
                var n = WidgetRegistry.variantOrDefault(id);
                var sz = WidgetRegistry.variantSize(id, n);
                console.log("CHECK registre " + id + " : dispo=" + ok
                            + " variantes=" + names + " défaut=" + n
                            + " taille=" + sz.w + "x" + sz.h
                            + " hôtes=" + WidgetRegistry.hosts(id).join(","));
            }
        }

        function dumpState() {
            console.log("CHECK playlist : polls=" + Playlist.polls + " posts=" + Playlist.posts
                        + " mpdOk=" + Playlist.mpdOk + " pistes=" + Playlist.count
                        + " courante=" + Playlist.currentPos + " shuffle=" + Playlist.shuffleOn);
            var c = win.calendarProbe.cells;
            var todayIdx = -1;
            for (var i = 0; i < c.length; ++i) {
                if (c[i].today)
                    todayIdx = i;
            }
            console.log("CHECK calendar : mois=" + win.calendarProbe.monthLabel
                        + " cellules=" + c.length + " aujourd'hui=index " + todayIdx
                        + " tâches du jour=" + win.calendarProbe.todayTasks
                        + " tâches datées du mois=" + win.calendarProbe.monthTasks.length);
            console.log("CHECK connectivity : moduleNet=" + Connectivity.hasNetworking
                        + " moduleBt=" + Connectivity.hasBluetooth
                        + " wpctl=" + Connectivity.hasWpctl
                        + " backend=" + Connectivity.netBackend
                        + " netReady=" + Connectivity.netReady);
            console.log("CHECK connectivity net : « " + Connectivity.netMain + " » / « "
                        + Connectivity.netSub + " »");
            console.log("CHECK connectivity bt  : « " + Connectivity.btMain + " » / « "
                        + Connectivity.btSub + " »");
            console.log("CHECK connectivity aud : « " + Connectivity.audioMain + " » / « "
                        + Connectivity.audioSub + " »");
            console.log("CHECK modes : dnd=" + Modes.flag("dnd") + " flou=" + Modes.flag("blur")
                        + " lite=" + Modes.flag("lite") + " nuit(proc)=" + Modes.flag("bluesun"));
            var keys = ["dnd", "blur", "bluesun", "lite"];
            for (var k = 0; k < keys.length; ++k) {
                console.log("  toggle " + keys[k] + " : dispo=" + Modes.available(keys[k])
                            + " état=" + Modes.flag(keys[k])
                            + (Modes.available(keys[k]) ? "" : " install=" + Modes.installFor(keys[k])));
            }
        }

        // Sonde de calcul : mêmes données que le widget (Env) et même
        // arithmétique que CalendarWidget.buildCells — elle sert aux
        // assertions console (le widget, lui, est chargé par le registre).
        Item {
            id: calcProbe
            visible: false
            readonly property var taskItems: (Env.tasks && Array.isArray(Env.tasks.items))
                                             ? Env.tasks.items : []
            readonly property string todayKey: {
                var d = Env.now;
                function p2(n) {
                    return (n < 10 ? "0" : "") + n;
                }
                return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate());
            }
            readonly property var cells: {
                var parts = calcProbe.todayKey.split("-");
                var y = parseInt(parts[0], 10);
                var m = parseInt(parts[1], 10) - 1;
                var items = calcProbe.taskItems;
                var byDay = {};
                for (var t = 0; t < items.length; ++t) {
                    var at = items[t] ? ("" + items[t].at) : "";
                    if (at.length < 10)
                        continue;
                    var k = at.substring(0, 10);
                    if (!byDay[k])
                        byDay[k] = [];
                    byDay[k].push(items[t]);
                }
                var lead = (new Date(y, m, 1).getDay() + 6) % 7;
                var out = [];
                for (var i = 0; i < 42; ++i) {
                    var d = new Date(y, m, 1 - lead + i);
                    function p2(n) {
                        return (n < 10 ? "0" : "") + n;
                    }
                    var key = d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate());
                    out.push({ day: d.getDate(), today: key === calcProbe.todayKey,
                               tasks: byDay[key] ? byDay[key] : [] });
                }
                return out;
            }
            readonly property var monthTasks: {
                var prefix = calcProbe.todayKey.substring(0, 7);
                var out = [];
                for (var i = 0; i < calcProbe.taskItems.length; ++i) {
                    var it = calcProbe.taskItems[i];
                    if (it && it.at && ("" + it.at).substring(0, 7) === prefix)
                        out.push(it);
                }
                return out;
            }
            readonly property int todayTasks: {
                for (var i = 0; i < calcProbe.cells.length; ++i) {
                    if (calcProbe.cells[i].today)
                        return calcProbe.cells[i].tasks.length;
                }
                return 0;
            }
            readonly property string monthLabel: {
                var p = calcProbe.todayKey.split("-");
                var mi = parseInt(p[1], 10) - 1;
                return Env.monthShort[mi] + " " + p[0];
            }
        }

        property var calendarProbe: calcProbe

        Timer {
            interval: 2400
            running: true
            repeat: false
            onTriggered: {
                win.dumpRegistry();
                win.dumpState();
                if (win.grabPath.length > 0) {
                    board.grabToImage(function (res) {
                        console.log("wave4-variants: capture 1 (données réelles) =", res.saveToFile(win.grabPath));
                    });
                }
            }
        }

        // ── Injection de harnais (jamais dans l'app) ──────────────────────
        // 1) une piste marquée courante pour prouver le repère de lecture ;
        // 2) trois tâches datées pour prouver le placement sur la grille.
        Timer {
            interval: 3400
            running: true
            repeat: false
            onTriggered: {
                Playlist.pollTimer.running = false;
                var copy = [];
                for (var i = 0; i < Playlist.tracks.length; ++i) {
                    var t = Playlist.tracks[i];
                    copy.push({ pos: t.pos, title: t.title, artist: t.artist, album: t.album,
                                duration: t.duration, current: i === 2 });
                }
                Playlist.tracks = copy;

                Env.tasksTimer.running = false;
                var d = Env.now;
                function p2(n) {
                    return (n < 10 ? "0" : "") + n;
                }
                function day(n) {
                    return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(n) + " 09:00";
                }
                var plus = (d.getDate() + 3 <= 28) ? d.getDate() + 3 : d.getDate() - 3;
                Env.tasks = {
                    items: [
                        { id: 1, text: "réviser le contrat widget", done: false, at: day(d.getDate()) },
                        { id: 2, text: "session design", done: false, at: day(plus) },
                        { id: 3, text: "livraison vague finale", done: false, at: day(Math.max(1, d.getDate() - 2)) }
                    ],
                    total: 3, done: 0
                };
                console.log("CHECK injection harnais : 1 piste marquée courante (pos 2), 3 tâches datées ("
                            + day(d.getDate()) + " / " + day(plus) + " / "
                            + day(Math.max(1, d.getDate() - 2)) + ")");
                win.dumpState();
            }
        }


        Timer {
            interval: 4400
            running: true
            repeat: false
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                var path2 = win.grabPath.replace(/\.png$/, "-current.png");
                board.grabToImage(function (res) {
                    console.log("wave4-variants: capture 2 (piste courante + tâches datées) =",
                                res.saveToFile(path2));
                });
            }
        }

        // ── Capture 3 : outil absent (hyprsunset) ─────────────────────────
        // Sur cette machine hyprsunset EST installé (/usr/bin) : on force donc
        // l'état de harnais pour prouver l'affichage « indisponible + commande
        // d'installation » demandé au contrat.
        Timer {
            interval: 5400
            running: true
            repeat: false
            onTriggered: {
                Modes.pollTimer.running = false;
                var st = JSON.parse(JSON.stringify(Modes.state));
                if (!st.env)
                    st.env = ({});
                st.env.hyprsunset = false;
                if (!st.real)
                    st.real = ({});
                st.real.bluesun = null;
                st.missing = [{ mode: "bluesun", tool: "hyprsunset",
                                install: "sudo pacman -S hyprsunset" }];
                Modes.state = st;
                console.log("CHECK simulation outil absent : hyprsunset=false → bluesun dispo="
                            + Modes.available("bluesun") + " install=" + Modes.installFor("bluesun"));
            }
        }

        Timer {
            interval: 6200
            running: true
            repeat: false
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                var path3 = win.grabPath.replace(/\.png$/, "-missing.png");
                board.grabToImage(function (res) {
                    console.log("wave4-variants: capture 3 (outil absent) =", res.saveToFile(path3));
                });
            }
        }
    }
}
