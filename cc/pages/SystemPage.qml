// SystemPage.qml — page « Système » du CC.
//
// Habillage v2 (spec microcopie §Style) : mêmes données et même route
// (/api/stats) que l'ancienne page, mais carte de verre (GlassCard) au lieu
// d'une tuile opaque, libellés en français, et distinction explicite entre
// « 0 % » (mesure réelle) et « Non mesuré » (donnée absente).
import QtQuick
import QtQuick.Layouts
import "../qml"
import Sasquatch.Widgets 1.0

Item {
    id: sysPage

    // Sondé par le shell ; repli sur la sonde partagée d'Env (page autonome).
    property var stats: Env.stats

    readonly property bool hasCpu: !!(stats && stats.cpu !== undefined)
    readonly property bool hasRam: !!(stats && stats.ram && stats.ram.pct !== undefined)
    readonly property bool hasGpu: !!(stats && stats.gpu && stats.gpu.util !== undefined)
    readonly property var st: stats || ({})

    // Même empilement serré que la page Outils (brief bugs §4) : Column, écart
    // Theme.spacing, aucune carte étirée sur la hauteur restante.
    Column {
        id: cards
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing

        GlassCard {
            // Hauteur naturelle du contenu (jauges + sparklines) : la carte
            // n'occupe plus un bloc de 260 px à moitié vide.
            width: cards.width
            title: "Utilisation"
            subtitle: "Processeur · Mémoire · Carte graphique"

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                Gauge {
                    pct: sysPage.hasCpu ? sysPage.st.cpu : 0
                    strokeColor: Theme.accent
                    label: "Processeur"
                    textColor: Theme.ink
                    labelColor: Theme.inkDim
                }
                Gauge {
                    pct: sysPage.hasRam ? sysPage.st.ram.pct : 0
                    strokeColor: Theme.accent2
                    label: "Mémoire"
                    textColor: Theme.ink
                    labelColor: Theme.inkDim
                }
                Gauge {
                    pct: sysPage.hasGpu ? sysPage.st.gpu.util : 0
                    strokeColor: Theme.warn
                    label: "Carte graph."
                    textColor: Theme.ink
                    labelColor: Theme.inkDim
                    showPct: sysPage.hasGpu
                }

                // « Non mesuré » plutôt que « 0 % » quand la sonde ne donne rien.
                Text {
                    visible: !sysPage.hasGpu
                    text: "Non mesuré"
                    color: Theme.inkDim
                    font.pixelSize: 10
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "Mém. vidéo", key: "vram", color: Theme.accent2 },
                            { label: "Temp. proc.", key: "cpu_temp", color: Theme.hot },
                            { label: "Temp. carte", key: "gpu_temp", color: Theme.warn },
                            { label: "Réseau", key: "down", color: Theme.accent }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: modelData.label
                                font.pixelSize: 10
                                color: Theme.inkDim
                                Layout.preferredWidth: 78
                                elide: Text.ElideRight
                            }
                            Sparkline {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                hist: (sysPage.stats && sysPage.stats.history
                                       && sysPage.stats.history[modelData.key])
                                      ? sysPage.stats.history[modelData.key] : []
                                lineColor: modelData.color
                            }
                        }
                    }
                }
            }
        }

        GlassCard {
            width: cards.width
            title: "Machine"
            subtitle: sysPage.st.distro || "—"

            RowLayout {
                Layout.fillWidth: true
                spacing: 18

                Repeater {
                    model: [
                        { k: "Processeur", v: sysPage.st.cpu || "—" },
                        { k: "Noyau", v: sysPage.st.kernel || "—" },
                        { k: "Session", v: sysPage.st.uptime || "—" }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: modelData.k; color: Theme.inkDim; font.pixelSize: 9 }
                        Text {
                            text: modelData.v
                            color: Theme.ink
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }

    }
}
