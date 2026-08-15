import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// ─────────────────────────────────────────────────────────────
//  愛子 (Aiko) — main.qml
//  Sidebar chat IA (droite, Super+N) — Quickshell 0.3.0.
//  Verre dépoli + palette dynamique (pattern CC/Settings).
//  Backend : server.py (port 8780), llama-server (port 8781).
// ─────────────────────────────────────────────────────────────
import Quickshell
import Quickshell.Hyprland

FloatingWindow {
    id: root

    // ── Thème (palette dynamique, poll /api/palette) ──
    property color cCard: Qt.rgba(0.08, 0.08, 0.12, 0.55)
    property color cBorder: Qt.rgba(0.4, 0.4, 0.5, 0.4)
    property color cText: "#e6e6ea"
    property color cDim: "#9a9aa5"
    property color cAccent: "#7aa2f7"
    property color cOverlay: Qt.rgba(0, 0, 0, 0.25)
    property color cUserBubble: Qt.rgba(0.3, 0.38, 0.62, 0.85)
    property color cAiBubble: Qt.rgba(0.16, 0.17, 0.24, 0.85)
    property color cInput: Qt.rgba(0.12, 0.13, 0.18, 0.9)
    // ── Chat state ──
    property var messages: []
    // [{role: "user"|"ai", text: "..."}]
    property string jobId: ""
    property bool generating: false
    property bool modelLoading: false
    property string pendingImage: "" // base64 de la capture attachée (pas envoyée)
    property string attachName: ""
    // L'image attachée part avec le message (stockée avant reset)
    property string lastImageData: ""

    // ── API helper ──
    function api(method, path, body, cb, timeoutMs) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = timeoutMs || 3000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var parsed = null;
                try {
                    parsed = JSON.parse(xhr.responseText);
                } catch (e) {
                }
                if (cb)
                    cb(xhr.status >= 200 && xhr.status < 300 ? parsed : null);

            }
        };
        xhr.ontimeout = xhr.onerror = function() {
            if (cb)
                cb(null);

        };
        try {
            xhr.open(method, "http://127.0.0.1:8780" + path);
            if (body !== null && body !== undefined) {
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.send(JSON.stringify(body));
            } else {
                xhr.send();
            }
        } catch (e) {
            if (cb)
                cb(null);

        }
    }

    // ── Modèle lazy : démarre llama-server à l'ouverture ──
    function startModel() {
        modelLoading = true;
        api("POST", "/api/model/start", {
        }, function(res) {
            if (res && res.ok) {
                modelLoading = false;
                statusDot.color = cAccent;
            } else {
                // Pas encore prêt → on poll le status
                modelPollTimer.start();
            }
        }, 5000);
    }

    function fetchPalette() {
        api("GET", "/api/palette", null, function(p) {
            if (!p)
                return ;

            if (p.bgSolid)
                cCard = Qt.rgba(0.07, 0.07, 0.1, 0.6);

            if (p.text)
                cText = p.text;

            if (p.textDim)
                cDim = p.textDim;

            if (p.accent)
                cAccent = p.accent;

            if (p.overlay)
                cOverlay = Qt.rgba(0, 0, 0, 0.25);

        });
    }

    // ── Envoyer un message ──
    function sendMessage() {
        var text = inputField.text.trim();
        if (text.length === 0 || generating)
            return;
        // L'image attachée (déjà affichée par doCapture) part avec le message
        var img = lastImage();
        messages.push({
            "role": "user",
            "text": text
        });
        messages.push({
            "role": "ai",
            "text": ""
        });
        msgList.positionViewAtEnd();
        inputField.text = "";
        generating = true;
        api("POST", "/api/chat", {
            "message": text,
            "image": img
        }, function(res) {
            if (res && res.ok) {
                jobId = res.job_id;
                pollTimer.start();
            } else {
                var err = res ? (res.error || "erreur") : "serveur injoignable";
                messages[messages.length - 1].text = "⚠ " + err;
                generating = false;
            }
        }, 5000);
    }

    function lastImage() {
        var img = lastImageData;
        lastImageData = "";
        return img;
    }

    // ── Capture (sélection de zone → attachée, PAS envoyée) ──
    function doCapture() {
        if (generating)
            return ;

        api("POST", "/api/capture", {
        }, function(res) {
            if (res && res.ok && res.image) {
                pendingImage = res.image;
                lastImageData = res.image;
                attachName = "capture " + new Date().toLocaleTimeString();
                messages.push({
                    "role": "img",
                    "text": attachName,
                    "data": pendingImage
                });
                msgList.positionViewAtEnd();
            } else if (res && res.error) {
                messages.push({
                    "role": "ai",
                    "text": "⚠ capture : " + res.error
                });
                msgList.positionViewAtEnd();
            }
        }, 20000);
    }

    // ── Reset / Save ──
    function newChat() {
        if (generating)
            return ;

        messages = [];
        api("POST", "/api/chat/reset", {
        }, null);
        inputField.forceActiveFocus();
    }

    function saveChat() {
        api("POST", "/api/session/save", {
            "name": "session"
        }, function(res) {
            if (res && res.ok) {
                messages.push({
                    "role": "ai",
                    "text": "💾 session sauvegardée : " + res.file
                });
                msgList.positionViewAtEnd();
            }
        }, 5000);
    }

    function quit() {
        api("POST", "/api/close", {
        }, null);
        Qt.quit();
    }

    title: "Aiko"
    // Fenêtre = UNIQUEMENT la sidebar (pas plein écran) → le reste de l'écran
    // reste visible et net. Marge en haut (waybar 42px + 20) et en bas (20).
    // Position : windowrule move 100%-440 62 (droite + marge).
    implicitWidth: 420
    implicitHeight: Screen.height - 42 - 40
    visible: true
    color: "transparent"
    // Animation d'ouverture (sur le panel, pas sur la FloatingWindow —
    // Quickshell 0.3.0 n'expose ni opacity ni scale ni flags au niveau fenêtre)
    Component.onCompleted: {
        startModel();
        fetchPalette();
        paletteTimer.start();
        inputField.forceActiveFocus();
    }

    // Fermeture : Escape ou ✕ (pas de voile cliquable — la fenêtre ne couvre
    // plus tout l'écran, le toggle Super+N ferme aussi)
    Shortcut {
        sequence: "Escape"
        enabled: !inputField.activeFocus || inputField.text.length === 0
        onActivated: root.quit()
    }

    Timer {
        id: modelPollTimer

        interval: 800
        repeat: true
        running: false
        onTriggered: {
            api("GET", "/api/model/status", null, function(res) {
                if (res && res.running) {
                    modelLoading = false;
                    statusDot.color = cAccent;
                    modelPollTimer.stop();
                }
            });
        }
    }

    Timer {
        id: paletteTimer

        interval: 2000
        repeat: true
        running: false
        onTriggered: fetchPalette()
    }

    // ── Poll du streaming ──
    Timer {
        id: pollTimer

        interval: 150
        repeat: true
        running: false
        onTriggered: {
            if (jobId === "") {
                pollTimer.stop();
                return ;
            }
            api("GET", "/api/chat/poll/" + jobId, null, function(res) {
                if (!res)
                    return ;

                var idx = messages.length - 1;
                if (idx >= 0 && messages[idx].role === "ai") {
                    messages[idx].text = res.text || "";
                    msgList.positionViewAtEnd();
                }
                if (res.done) {
                    pollTimer.stop();
                    generating = false;
                    jobId = "";
                    if (res.error)
                        messages[idx].text = "⚠ " + res.error;

                }
            });
        }
    }

    // ══════════════════════════════════════════════════════════
    //  UI
    // ══════════════════════════════════════════════════════════
    // Panel flottant : marge tout autour (effet carte), coins arrondis.
    Rectangle {
        id: panel

        anchors.fill: parent
        anchors.margins: 16
        color: cCard
        border.color: cBorder
        border.width: 1
        radius: 20

        // Animation d'ouverture (pattern CC : sur l'élément, pas la fenêtre)
        opacity: 0
        scale: 0.98
        Component.onCompleted: {
            opacity = 1;
            scale = 1;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }

        }
        Behavior on scale {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }

        }

        // MouseArea « swallow » : les clics sur le vide du panel ne ferment pas
        MouseArea {
            anchors.fill: parent
            onClicked: panel.forceActiveFocus()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    id: statusDot

                    width: 10
                    height: 10
                    radius: 5
                    color: cDim
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: "愛子"
                    font.pixelSize: 18
                    font.bold: true
                    color: cText
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: modelLoading ? "… chargement modèle" : (generating ? "● génération…" : "prête")
                    font.pixelSize: 11
                    color: cDim
                    Layout.alignment: Qt.AlignVCenter
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: "💾"
                    font.pixelSize: 14
                    color: cDim
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: saveChat()
                        hoverEnabled: true
                    }

                }

                Text {
                    text: "✕"
                    font.pixelSize: 16
                    color: cDim
                    Layout.alignment: Qt.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.quit()
                        hoverEnabled: true
                    }

                }

            }

            // ── Zone messages ──
            Flickable {
                id: msgList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: msgCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: msgCol

                    width: msgList.width
                    spacing: 8

                    Repeater {
                        model: root.messages

                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: bubble.implicitHeight + 8

                            // Bulle user → droite, IA → gauche
                            Rectangle {
                                id: bubble

                                width: Math.min(parent.width * 0.82, implicitWidth + 24)
                                height: implicitHeight + 16
                                radius: 14
                                color: modelData.role === "user" ? cUserBubble : (modelData.role === "img" ? Qt.rgba(0.2, 0.2, 0.3, 0.6) : cAiBubble)
                                anchors.right: modelData.role === "user" ? parent.right : undefined
                                anchors.left: modelData.role === "user" ? undefined : parent.left
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    Image {
                                        visible: modelData.role === "img"
                                        source: modelData.data ? ("data:image/png;base64," + modelData.data) : ""
                                        Layout.preferredWidth: 180
                                        Layout.preferredHeight: 120
                                        fillMode: Image.PreserveAspectFit
                                        clip: true
                                    }

                                    Text {
                                        visible: modelData.role === "img"
                                        text: modelData.text
                                        font.pixelSize: 10
                                        color: cDim
                                    }

                                    Text {
                                        visible: modelData.role !== "img"
                                        text: modelData.text || "…"
                                        font.pixelSize: 13
                                        color: modelData.role === "user" ? "#ffffff" : cText
                                        textFormat: Text.PlainText
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                }

                            }

                        }

                    }

                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

            }

            // ── Input bar ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: inputRow.implicitHeight + 16
                color: cInput
                radius: 14
                border.color: cBorder
                border.width: 1

                RowLayout {
                    id: inputRow

                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "📷"
                        font.pixelSize: 16
                        color: cDim
                        Layout.alignment: Qt.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.doCapture()
                            hoverEnabled: true
                        }

                    }

                    TextField {
                        id: inputField

                        Layout.fillWidth: true
                        placeholderText: modelLoading ? "chargement du modèle…" : "Message à 愛子…"
                        placeholderTextColor: cDim
                        color: cText
                        font.pixelSize: 13
                        onAccepted: root.sendMessage()

                        background: Rectangle {
                            color: "transparent"
                        }

                    }

                    Text {
                        text: "➤"
                        font.pixelSize: 15
                        color: generating ? cDim : cAccent
                        Layout.alignment: Qt.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.sendMessage()
                            enabled: !generating
                            hoverEnabled: true
                        }

                    }

                }

            }

            // ── Boutons bas ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "nouveau"
                    font.pixelSize: 11
                    color: cDim
                    Layout.alignment: Qt.AlignLeft

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.newChat()
                        hoverEnabled: true
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: "Échap = fermer"
                    font.pixelSize: 10
                    color: cDim
                    Layout.alignment: Qt.AlignRight
                }

            }

        }

    }

}
