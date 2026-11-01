// widgets-variants.qml — preuve combinée des 5 widgets v1d (+ correctifs média).
//
// Une SEULE capture (SASQUATCH_HARNESS_GRAB) montre, avec les données RÉELLES
// du serveur : weather (compact/normal/hero), resources (compact/normal/hero),
// tasks (compact/normal), volume (compact/normal), battery (compact/normal),
// et le média en hero + normal pour prouver les correctifs (a) cava lisible,
// (b) barre de progression sur sa propre ligne, (c) hero distribué.
//
// Jamais le CC plein écran : surface 1240x1056, layer Top, exclusiveZone 0.
//
// Lancement :
//   QML_IMPORT_PATH=$HOME/.config/cc/widgets \
//   SASQUATCH_HARNESS_GRAB=/tmp/widgets-variants.png \
//   timeout 20 quickshell -p cc/widgets/tests/widgets-variants.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import Sasquatch.Widgets 1.0

ShellRoot {
    PanelWindow {
        id: win

        implicitWidth: 1240
        implicitHeight: 1056

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "sasquatch-widgets-variants"
        WlrLayershell.exclusiveZone: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: true
        }
        margins {
            top: 12
            left: 16
        }

        readonly property string grabPath: {
            var v = Quickshell.env("SASQUATCH_HARNESS_GRAB");
            return (typeof v === "string") ? v : "";
        }

        // Le composant vient du REGISTRE uniquement (brief §4).
        component W: Loader {
            id: w

            property string typeId: ""
            property string varName: "normal"
            property string tag: ""
            property var styleObj: ({ alpha: 0.24, accent: "auto", blur: 9, radius: 16 })

            source: WidgetRegistry.component(w.typeId)

            onLoaded: {
                w.item.instanceId = "chk-" + w.tag;
                w.item.host = "cc";
                w.item.variant = w.varName;
                w.item.editing = false;
                w.item.style = w.styleObj;
                w.item.options = WidgetRegistry.defaultOptions(w.typeId);
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

            // Bandeau de preuve : registre, API, valeurs réellement lues.
            Text {
                id: status
                x: 20
                y: 4
                width: parent.width - 40
                text: "widgets v1d — " + WidgetRegistry.entries.length + " entrées au registre"
                      + " · api " + (Api.online ? "ok" : "hors ligne")
                      + " · accent lum " + Theme.luminance(Theme.accent).toFixed(3)
                      + " → cava " + (Theme.luminance(Theme.accent) < Theme.vizMinLum ? "dérivé" : "accent")
                      + " · météo " + (Env.weather.ok === true ? (Env.weather.temp + "° " + Env.weather.city) : "—")
                      + " · cpu " + Math.round(Env.stats.cpu ? Env.stats.cpu : 0) + "%"
                      + " · tâches " + Env.tasks.done + "/" + Env.tasks.total
                      + " · vol " + Env.volume + (Env.muted ? " muet" : "")
                      + " · lum " + Env.brightness
                      + " · batt " + Env.batteryPct + "% " + Env.batteryState
                color: Theme.inkDim
                font.pixelSize: 12
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            // ── Rangée 1 : média hero + tâches normal + 3 compacts ────────
            W {
                x: 20
                y: 34
                typeId: "media"
                varName: "hero"
                tag: "media-hero"
                styleObj: ({ alpha: 0.15, accent: "auto", blur: 9, radius: 16 })
            }

            W {
                x: 600
                y: 34
                typeId: "tasks"
                varName: "normal"
                tag: "tasks-normal"
            }

            W {
                x: 980
                y: 34
                typeId: "tasks"
                varName: "compact"
                tag: "tasks-compact"
            }

            W {
                x: 980
                y: 110
                typeId: "volume"
                varName: "compact"
                tag: "vol-compact"
            }

            W {
                x: 980
                y: 186
                typeId: "battery"
                varName: "compact"
                tag: "batt-compact"
            }

            // ── Rangée 2 : météo ─────────────────────────────────────────
            W {
                x: 20
                y: 304
                typeId: "weather"
                varName: "hero"
                tag: "weather-hero"
                styleObj: ({ alpha: 0.15, accent: "auto", blur: 9, radius: 16 })
            }

            W {
                x: 600
                y: 304
                typeId: "weather"
                varName: "normal"
                tag: "weather-normal"
            }

            W {
                x: 980
                y: 304
                typeId: "weather"
                varName: "compact"
                tag: "weather-compact"
            }

            // ── Rangée 3 : ressources ────────────────────────────────────
            W {
                x: 20
                y: 574
                typeId: "resources"
                varName: "hero"
                tag: "res-hero"
                styleObj: ({ alpha: 0.15, accent: "auto", blur: 9, radius: 16 })
            }

            W {
                x: 600
                y: 574
                typeId: "resources"
                varName: "normal"
                tag: "res-normal"
            }

            W {
                x: 980
                y: 574
                typeId: "resources"
                varName: "compact"
                tag: "res-compact"
            }

            // ── Rangée 4 : volume normal, batterie normal, média normal ──
            W {
                x: 20
                y: 844
                typeId: "volume"
                varName: "normal"
                tag: "vol-normal"
            }

            W {
                x: 400
                y: 844
                typeId: "battery"
                varName: "normal"
                tag: "batt-normal"
            }

            W {
                x: 780
                y: 844
                typeId: "media"
                varName: "normal"
                tag: "media-normal"
            }
        }

        // Valeurs cava synthétiques : rien ne joue sur la machine (le lecteur
        // est en pause). Les hauteurs sont donc injectées pour que la preuve
        // montre la géométrie et la teinte des barres ; le TEXTE (titre,
        // artiste, source) reste la donnée réelle du serveur.
        Timer {
            interval: 700
            running: true
            repeat: false
            onTriggered: {
                Music.vizTimer.running = false;
                var vals = [];
                for (var i = 0; i < 20; ++i)
                    vals.push(Math.abs(Math.sin(i * 0.7)) * 0.85 + 0.05);
                Music.vizVals = vals;
                console.log("CHECK cava : poll viz gelé, valeurs synthétiques ("
                            + Music.vizVals.length + ") · teinte dérivée "
                            + Theme.vizA + " alpha live " + Theme.vizAlpha);
            }
        }

        // Assertions imprimées (console) : registre + résolution + données.
        Timer {
            interval: 1500
            running: true
            repeat: false
            onTriggered: {
                var ids = ["weather", "resources", "tasks", "volume", "battery"];
                for (var i = 0; i < ids.length; ++i) {
                    console.log("CHECK registre " + ids[i]
                                + " : composant=" + (WidgetRegistry.isAvailable(ids[i]) ? "ok" : "MANQUANT")
                                + " variantes=" + WidgetRegistry.variantNames(ids[i]).join("/")
                                + " hôtes=" + WidgetRegistry.hosts(ids[i]).join("/")
                                + " taille normal=" + WidgetRegistry.variantSize(ids[i], "normal").w
                                + "x" + WidgetRegistry.variantSize(ids[i], "normal").h);
                }
                console.log("CHECK meteo : ok=" + Env.weather.ok + " ville=" + Env.weather.city
                            + " temp=" + Env.weather.temp + " code=" + Env.weather.code
                            + " libelle=" + Env.weather.label
                            + " · prévision fournie par le serveur = "
                            + (Array.isArray(Env.weather.daily) || Array.isArray(Env.weather.forecast)
                               ? "oui" : "non (ligne 3 jours masquée)"));
                console.log("CHECK stats : cpu=" + Env.stats.cpu + " ram="
                            + (Env.stats.ram ? Env.stats.ram.pct : "—") + " gpu="
                            + (Env.stats.gpu ? Env.stats.gpu.util : "—") + " temp=" + Env.stats.cpu_temp
                            + " historique=" + (Env.stats.history && Array.isArray(Env.stats.history.cpu)
                                                ? Env.stats.history.cpu.length + " points" : "aucun"));
                console.log("CHECK taches : " + JSON.stringify(Env.tasks).substring(0, 180));
                console.log("CHECK son : volume=" + Env.volume + " muted=" + Env.muted
                            + " · luminosite=" + Env.brightness);
                console.log("CHECK batterie : pct=" + Env.batteryPct + " etat=" + Env.batteryState
                            + " power_now=" + Env.batteryPower + "µW energy_now=" + Env.batteryEnergy
                            + "µWh energy_full=" + Env.batteryEnergyFull + "µWh autonomie="
                            + Env.batteryMinutes + "min");
            }
        }

        // Preuve des ÉCRITURES du widget tâches : le même chemin que le clic
        // (Env.addTask / Env.toggleTask → POST /api/tasks avec le format exact
        // du serveur). Les deux tâches créées sont retirées par curl après le
        // test : la liste réelle de momo est rendue à son état d'origine.
        Timer {
            interval: 1000
            running: true
            repeat: false
            onTriggered: Env.addTask("vérifier le cava du média")
        }

        Timer {
            interval: 1700
            running: true
            repeat: false
            onTriggered: Env.addTask("ranger le bureau")
        }

        Timer {
            interval: 2400
            running: true
            repeat: false
            onTriggered: {
                if (Env.tasks.items.length > 0)
                    Env.toggleTask(Env.tasks.items[0].id);
                console.log("CHECK taches POST : total=" + Env.tasks.total
                            + " done=" + Env.tasks.done
                            + " items=" + JSON.stringify(Env.tasks.items));
            }
        }

        // Rendu autonome (les surfaces layer ne sont pas capturables ici).
        Timer {
            interval: 3000
            running: win.grabPath.length > 0
            repeat: false
            onTriggered: {
                if (win.grabPath.length === 0)
                    return;
                var v = Music.vizVals;
                console.log("CHECK cava au grab : n=" + v.length
                            + " max=" + (v.length > 0 ? Math.max.apply(null, v).toFixed(2) : "—")
                            + " · polls viz=" + Music.vizPolls);
                board.grabToImage(function (res) {
                    console.log("widgets-variants: rendu écrit =", res.saveToFile(win.grabPath));
                });
            }
        }
    }
}
