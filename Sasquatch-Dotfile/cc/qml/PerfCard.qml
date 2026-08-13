// Sasquatch Control Center — PerfCard.qml
// CPU / RAM / GPU / températures / réseau / uptime — polling 1 s.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    property var stats: ({})
    property var hist: ({})

    // couleurs du thème exposées au delegate (Palette n'est pas résolu
    // dans les contexts de Repeater avec modèles JS — passer par le root)
    readonly property color cBg: Palette.bgSolid
    readonly property color cBorder: Palette.accent2
    readonly property color cDim: Palette.textDim
    readonly property color cText: Palette.text
    readonly property color cAccent: Palette.accent
    readonly property color cGood: Palette.good
    readonly property color cWarn: Palette.warn
    readonly property color cHot: Palette.hot

    property var minis: [
        { label: "CPU", key: "cpu", c: "accent", max: 100 },
        { label: "RAM", key: "ram", c: "good", max: 100 },
        { label: "GPU", key: "gpu", c: "warn", max: 100 },
        { label: "VRAM", key: "vram", c: "hot", max: 6144 },
        { label: "Temp CPU", key: "cpu_temp", c: "warn", max: 100 },
        { label: "Temp GPU", key: "gpu_temp", c: "hot", max: 100 },
        { label: "Réseau ↓", key: "net", c: "good", max: 100 }
    ]

    function sparkColor(c) {
        switch (c) {
            case "good": return root.cGood;
            case "warn": return root.cWarn;
            case "hot": return root.cHot;
            default: return root.cAccent;
        }
    }

    function textFor(key) {
        var s = root.stats;
        switch (key) {
            case "cpu": return s.cpu != null ? Math.round(s.cpu) + "%" : "—";
            case "ram": return s.ram && s.ram.pct != null ? Math.round(s.ram.pct) + "%" : "—";
            case "gpu": return s.gpu ? s.gpu.util + "%" : "indispo";
            case "vram": return s.gpu ? s.gpu.vram_used + " Mo" : "indispo";
            case "cpu_temp": return s.cpu_temp != null ? Math.round(s.cpu_temp) + "°C" : "indispo";
            case "gpu_temp": return s.gpu ? s.gpu.temp + "°C" : "indispo";
            case "net": return s.net ? fmtKBs(s.net.down) : "—";
        }
        return "—";
    }

    function valuesFor(key) {
        var h = root.hist;
        return (key === "net") ? (h.down || []) : (h[key] || []);
    }

    function fmtKBs(k) {
        if (k == null) return "—";
        if (k < 1024) return Math.round(k) + " Ko/s";
        return (k / 1024).toFixed(2) + " Mo/s";
    }

    function fmtUptime(s) {
        if (!s) return "—";
        var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        return (d ? d + "j " : "") + (h ? h + "h " : "") + m + "m";
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: Api.get("/api/stats", function(s) {
            if (!s) return;
            root.stats = s;
            root.hist = s.history || {};
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            Text { text: "⚡ Performance"; font.pixelSize: 13; font.bold: true; color: Palette.text }
            Item { Layout.fillWidth: true }
            Text {
                text: "uptime " + root.fmtUptime(root.stats.uptime)
                font.pixelSize: 9
                color: Palette.textDim
            }
        }

        // ── gauges + cores ──
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            spacing: 14

            ColumnLayout { // CPU
                Layout.preferredWidth: 130
                spacing: 0
                Gauge {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    value: root.stats.cpu || 0
                    color: Palette.accent
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5
                    Text {
                        text: root.stats.cpu != null ? Math.round(root.stats.cpu) + "%" : "—"
                        font.pixelSize: 17; font.bold: true; color: Palette.text
                    }
                    Text { text: "CPU"; font.pixelSize: 9; color: Palette.textDim }
                }
            }

            // cores
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4
                Repeater {
                    model: root.stats.cores || []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Palette.bgSolid
                            radius: 3
                            clip: true
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: Math.max(2, parent.height * (modelData / 100))
                                color: Palette.accent
                                radius: 3
                                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            text: index
                            font.pixelSize: 8; color: Palette.textDim
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            ColumnLayout { // RAM
                Layout.preferredWidth: 130
                spacing: 0
                Gauge {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    value: (root.stats.ram && root.stats.ram.pct) || 0
                    color: Palette.good
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5
                    Text {
                        text: root.stats.ram && root.stats.ram.pct != null ? Math.round(root.stats.ram.pct) + "%" : "—"
                        font.pixelSize: 17; font.bold: true; color: Palette.text
                    }
                    Text { text: "RAM"; font.pixelSize: 9; color: Palette.textDim }
                }
            }

            ColumnLayout { // GPU
                Layout.preferredWidth: 130
                spacing: 0
                Gauge {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    value: (root.stats.gpu && root.stats.gpu.util) || 0
                    color: Palette.warn
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5
                    Text {
                        text: root.stats.gpu ? root.stats.gpu.util + "%" : "—"
                        font.pixelSize: 17; font.bold: true; color: Palette.text
                    }
                    Text { text: "GPU"; font.pixelSize: 9; color: Palette.textDim }
                }
            }
        }

        // ── minis ──
        GridLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 78
            columns: 7
            flow: GridLayout.LeftToRight
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: root.minis
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.cBg
                    radius: 8
                    border.color: root.cBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2
                        Text {
                            text: modelData.label.toUpperCase()
                            font.pixelSize: 8; color: root.cDim
                        }
                        Text {
                            text: root.textFor(modelData.key)
                            font.pixelSize: 11; font.bold: true; color: root.cText
                        }
                        Spark {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            values: root.valuesFor(modelData.key)
                            color: root.sparkColor(modelData.c)
                            maxValue: modelData.max
                        }
                    }
                }
            }
        }
    }
}
