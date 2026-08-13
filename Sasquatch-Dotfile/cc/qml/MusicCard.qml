// Sasquatch Control Center — MusicCard.qml
// Now Playing (MPD) : pochette + égaliseur (cava) + progression + contrôles.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    color: Palette.card
    radius: 14
    border.color: Palette.accent2

    property var music: ({})
    property string lastFile: ""

    function fmtTime(s) {
        if (s == null || isNaN(s)) return "0:00";
        s = Math.floor(s);
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }
    function progressPct() {
        var d = root.music.duration || 0;
        if (d <= 0) return 0;
        return Math.max(0, Math.min(1, (root.music.elapsed || 0) / d));
    }
    function setVol(x) {
        var v = Math.max(0, Math.min(100, Math.round(x / volTrack.width * 100)));
        Api.post("/api/music/volume", { v: v });
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: Api.get("/api/music/status", function(s) {
            if (!s) return;
            root.music = s;
            if (s.file && s.file !== root.lastFile) {
                root.lastFile = s.file;
                coverImg.source = Api.base + "/albumart?t=" + Date.now();
                coverImg.visible = true;
            }
        })
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            Text { text: "🎵 Now Playing"; font.pixelSize: 13; font.bold: true; color: Palette.text }
            Item { Layout.fillWidth: true }
            Text {
                text: root.music.playing ? "▶ lecture" : root.music.paused ? "⏸ pause" : "⏹ arrêt"
                font.pixelSize: 9; color: Palette.textDim
            }
        }

        // ── now playing ──
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // pochette
            Rectangle {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                radius: 10
                color: Palette.cardSolid
                border.color: Palette.accent2
                clip: true

                Text {
                    id: coverFallback
                    anchors.centerIn: parent
                    text: "🎵"
                    font.pixelSize: 28
                    visible: !coverImg.visible
                }
                Image {
                    id: coverImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    onStatusChanged: {
                        if (coverImg.status === Image.Error) coverImg.visible = false;
                        if (coverImg.status === Image.Ready) coverImg.visible = true;
                    }
                }
            }

            // infos + contrôles
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 2

                Text {
                    text: root.music.artist || "—"
                    font.pixelSize: 10; color: Palette.textDim
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
                Text {
                    text: root.music.title || (root.music.file ? String(root.music.file).split("/").pop() : "Aucun morceau en cours")
                    font.pixelSize: 14; font.bold: true; color: Palette.text
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
                Text {
                    text: root.music.album || ""
                    font.pixelSize: 9; color: Palette.textDim
                    elide: Text.ElideRight; Layout.fillWidth: true
                }

                // timeline cliquable
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    color: "transparent"

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Palette.accent2
                        Rectangle {
                            width: parent.width * root.progressPct()
                            height: parent.height
                            radius: 2
                            color: Palette.accent
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                    }
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        Text { text: root.fmtTime(root.music.elapsed); font.pixelSize: 8; color: Palette.textDim }
                        Item { Layout.fillWidth: true }
                        Text { text: root.fmtTime(root.music.duration); font.pixelSize: 8; color: Palette.textDim }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var dur = root.music.duration || 0;
                            if (dur > 0) {
                                var pos = Math.floor(mouse.x / width * dur);
                                Api.post("/api/music/seek", { pos: pos });
                            }
                        }
                    }
                }

                // contrôles
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    spacing: 8

                    Btn { label: "⏮"; onClicked: Api.post("/api/music/prev") }
                    Btn {
                        label: root.music.playing ? "⏸" : "▶"
                        big: true
                        onClicked: Api.post("/api/music/toggle")
                    }
                    Btn { label: "⏭"; onClicked: Api.post("/api/music/next") }

                    // volume
                    Rectangle {
                        id: volTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Palette.accent2

                        Rectangle {
                            width: volTrack.width * (root.music.volume || 0) / 100
                            height: parent.height
                            radius: 3
                            color: Palette.accent
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: -30
                            text: (root.music.volume || 0) + "%"
                            font.pixelSize: 9; color: Palette.textDim
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: root.setVol(mouse.x)
                            onPositionChanged: if (pressed) root.setVol(mouse.x)
                        }
                    }
                }
            }

            // égaliseur (cava)
            Row {
                id: vizRow
                Layout.preferredWidth: 96
                Layout.preferredHeight: 84
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                clip: true

                property color barColor: Palette.accent

                ListModel { id: vizModel }

                Component.onCompleted: {
                    for (var i = 0; i < 20; i++) vizModel.append({ v: 0.05 });
                }

                Repeater {
                    model: vizModel
                    Rectangle {
                        required property var modelData
                        width: 3
                        height: 8 + modelData.v * 70
                        anchors.bottom: parent.bottom
                        radius: 1.5
                        color: vizRow.barColor
                        Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // ── polling égaliseur (cava, 100 ms) ──
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: Api.get("/api/viz", function(d) {
            if (!d || !d.vals) return;
            var vals = d.vals;
            for (var i = 0; i < 20 && i < vals.length; i++) {
                vizModel.set(i, { v: Math.max(0.05, vals[i]) });
            }
        })
    }
}
