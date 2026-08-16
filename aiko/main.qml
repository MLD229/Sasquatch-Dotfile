import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
// ─────────────────────────────────────────────────────────────
//  愛子 (Aiko) — main.qml
//  Sidebar chat IA (droite, Super+N) — Quickshell 0.3.0.
//  Verre dépoli + palette dynamique (pattern CC/Settings).
//  Backend : server.py (port 8780), llama-server (port 8781).
//  ─────────────────────────────────────────────────────────────
//  Chat enrichi (2026-08-15) :
//    - messages = ListModel (roles role/text/data/ts) : un tableau JS
//      ne réagissait NI à push() NI aux mutations en place → aucune bulle
//      n'apparaissait à l'envoi (bug #1). ListModel.append/set → Repeater
//      recrée/met à jour le delegate (prouvé headless).
//    - Géométrie des bulles pilotée par le CONTENU (ColumnLayout interne
//      contentCol.implicitHeight) et non par l'implicit d'un Rectangle
//      (toujours 0 — bug #2 : bulles écrasées).
//    - Timestamp HH:MM sur chaque message (model.ts, epoch).
//    - Historique persisté côté backend (autosave) + restauré à l'ouverture.
//    - TextArea multiligne : Entrée = envoyer, Shift+Entrée = nouvelle ligne.
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
    // ListModel (PAS un tableau JS : un tableau ne déclenche pas le Repeater
    // sur push()/mutation — bug #1). Roles : role, text, data, ts.
    property ListModel messages: ListModel {}
    property string jobId: ""
    property bool generating: false
    property bool modelLoading: false
    // Statut honnête : « prête » seulement si le modèle est VRAIMENT chargé.
    // serverDown = backend 8780 injoignable (≠ modèle en chargement).
    property bool serverDown: false
    property int pollFails: 0
    property color cBad: Qt.rgba(0.92, 0.35, 0.35, 1)
    property string pendingImage: "" // base64 de la capture attachée (pas envoyée)
    property string attachName: ""
    // L'image attachée part avec le message (stockée avant reset)
    property string lastImageData: ""

    // ── Format timestamp epoch → HH:MM (affiché sous chaque bulle) ──
    function fmtTime(ts) {
        if (!ts)
            return "";
        var d = new Date(ts * 1000);
        var h = d.getHours();
        var m = d.getMinutes();
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    // ── Scroll en fin de liste ──
    // ⚠️ PAS positionViewAtEnd() : c'est une méthode de ListView, pas de
    // Flickable (TypeError réelle vue au runtime). On anime contentY vers
    // le bas (le Behavior on contentY du Flickable rend le scroll fluide).
    function scrollToEnd() {
        var target = Math.max(0, msgList.contentHeight - msgList.height);
        msgList.contentY = target;
    }

    // ── Restauration de l'historique persisté (autosave backend) ──
    // Retry : au toggle ON, le backend peut être en train de démarrer (ou de
    // mourir si on rouvre vite après une fermeture) → le 1er GET peut échouer.
    // Sans retry, le chat s'ouvre VIDE alors que l'autosave contient tout
    // (bug « le chat se libère à la réouverture », signalé 2026-08-15).
    property int historyRetries: 0
    readonly property int maxHistoryRetries: 8
    function restoreHistory() {
        api("GET", "/api/history", null, function(res) {
            if (!res) {
                // Backend injoignable (relance en cours) → re-essaie bientôt
                if (historyRetries < maxHistoryRetries) {
                    historyRetries++;
                    historyRetryTimer.start();
                }
                return;
            }
            historyRetries = 0;
            if (!res.ok || !res.messages || res.messages.length === 0)
                return;
            for (var i = 0; i < res.messages.length; i++) {
                var m = res.messages[i];
                messages.append({
                    "role": m.role === "assistant" ? "ai" : "user",
                    "text": m.content,
                    "data": "",
                    "ts": m.ts || 0
                });
            }
            scrollToEnd();
        });
    }

    Timer {
        id: historyRetryTimer

        interval: 600
        repeat: false
        onTriggered: root.restoreHistory()
    }

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
                // statusDot.color = binding ternaire (suit cAccent/cDim/cBad)
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
        var now = Date.now() / 1000;
        messages.append({
            "role": "user",
            "text": text,
            "data": "",
            "ts": now
        });
        // Bulle IA vide → remplie au fil du streaming par le poll
        messages.append({
            "role": "ai",
            "text": "",
            "data": "",
            "ts": now
        });
        scrollToEnd();
        inputField.text = "";
        inputField.forceActiveFocus();
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
                var idx = messages.count - 1;
                var cur = messages.get(idx);
                messages.set(idx, {
                    "role": cur.role,
                    "text": "⚠ " + err,
                    "data": cur.data || "",
                    "ts": cur.ts
                });
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
                messages.append({
                    "role": "img",
                    "text": attachName,
                    "data": pendingImage,
                    "ts": 0
                });
                scrollToEnd();
            } else if (res && res.error) {
                messages.append({
                    "role": "ai",
                    "text": "⚠ capture : " + res.error,
                    "data": "",
                    "ts": 0
                });
                scrollToEnd();
            }
        }, 20000);
    }

    // ── Reset / Save ──
    function newChat() {
        if (generating)
            return;

        messages.clear();
        api("POST", "/api/chat/reset", {
        }, null);
        inputField.forceActiveFocus();
    }

    function saveChat() {
        api("POST", "/api/session/save", {
            "name": "session"
        }, function(res) {
            if (res && res.ok) {
                messages.append({
                    "role": "ai",
                    "text": "💾 session sauvegardée : " + res.file,
                    "data": "",
                    "ts": 0
                });
                scrollToEnd();
            }
        }, 5000);
    }

    // Fermeture : le POST /api/close est ASYNCHRONE (XHR QML) — Qt.quit()
    // immédiat couperait le socket avant l'envoi → le backend resterait vivant
    // (lazy cassé, VRAM occupée, et à la réouverture le chat peut sembler
    // « perdu »). On laisse 400 ms au POST pour partir, PUIS on quitte.
    Timer {
        id: quitTimer

        interval: 400
        repeat: false
        running: false
        onTriggered: Qt.quit()
    }

    function quit() {
        api("POST", "/api/close", {
        }, null);
        quitTimer.start();
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
        restoreHistory();
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
                // Backend injoignable : compteur d'échecs → « hors ligne »
                // après 3 polls ratés (~2,4 s), pas « prête » mensongère.
                if (!res) {
                    pollFails++;
                    if (pollFails >= 3) {
                        modelLoading = false;
                        serverDown = true;
                        modelPollTimer.stop();
                    }
                    return;
                }
                pollFails = 0;
                serverDown = false;
                // loaded = modèle VRAIMENT chargé (data non vide) — pas juste
                // le port qui écoute (bug « prête » pendant le chargement).
                if (res.loaded) {
                    modelLoading = false;
                    modelPollTimer.stop();
                } else {
                    modelLoading = true;
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
        // Anti-blocage : si le backend meurt PENDANT une génération, le poll
        // renvoie null à l'infini → generating resterait true (bloqué). Après
        // POLL_MAX_FAILS échecs (~4,5 s) on abandonne proprement.
        property int fails: 0
        readonly property int maxFails: 30
        onTriggered: {
            if (jobId === "") {
                pollTimer.stop();
                return ;
            }
            api("GET", "/api/chat/poll/" + jobId, null, function(res) {
                if (!res) {
                    pollTimer.fails++;
                    if (pollTimer.fails >= pollTimer.maxFails) {
                        pollTimer.stop();
                        pollTimer.fails = 0;
                        generating = false;
                        jobId = "";
                        // Marque la dernière bulle (IA) comme interrompue
                        var idx = messages.count - 1;
                        if (idx >= 0) {
                            var cur = messages.get(idx);
                            if (cur.role === "ai") {
                                messages.set(idx, {
                                    "role": "ai",
                                    "text": (cur.text || "") + "\n⚠ backend perdu (serveur arrêté)",
                                    "data": cur.data || "",
                                    "ts": cur.ts
                                });
                            }
                        }
                        serverDown = true;
                    }
                    return;
                }

                pollTimer.fails = 0;
                var idx = messages.count - 1;
                if (idx >= 0) {
                    var cur = messages.get(idx);
                    if (cur.role === "ai") {
                        // set() REMPLACE tout l'élément → préserver role/data/ts
                        messages.set(idx, {
                            "role": "ai",
                            "text": res.text || "",
                            "data": cur.data || "",
                            "ts": cur.ts
                        });
                        scrollToEnd();
                    }
                }
                if (res.done) {
                    pollTimer.stop();
                    pollTimer.fails = 0;
                    generating = false;
                    jobId = "";
                    if (res.error && idx >= 0) {
                        var cur2 = messages.get(idx);
                        messages.set(idx, {
                            "role": cur2.role,
                            "text": "⚠ " + res.error,
                            "data": cur2.data || "",
                            "ts": cur2.ts
                        });
                    }
                }
            });
        }
    }

    // ══════════════════════════════════════════════════════════
    //  UI
    // ══════════════════════════════════════════════════════════
    // La fenêtre EST l'interface : le panel remplit TOUTE la fenêtre
    // (pas de « page » visible autour — l'effet carte avec marge a été
    // supprimé sur demande momo 2026-08-15). Coins arrondis = forme de
    // l'interface elle-même. AUCUNE bordure (cadre supprimé).
    Rectangle {
        id: panel

        anchors.fill: parent
        color: cCard
        radius: 14

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
            // ⚠️ Padding ≥ radius (14) : le contenu du header/input tombe
            // dans les coins arrondis sinon (statusDot rogné — vérifié par
            // capture grim : pixels du header = wallpaper, pas le dot).
            anchors.margins: 18
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
                    // ⚠️ BINDING ternaire, PAS d'assignation dans un callback :
                    // `statusDot.color = cAccent` copie la valeur À CE MOMENT —
                    // si fetchPalette met à jour cAccent APRÈS, le dot reste
                    // figé (bug : dot bleu alors que la palette est rose).
                    color: serverDown ? cBad : (modelLoading ? cDim : cAccent)
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
                    text: serverDown ? "hors ligne" : (modelLoading ? "… chargement modèle" : (generating ? "● génération…" : "prête"))
                    font.pixelSize: 11
                    color: serverDown ? cBad : cDim
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
                // Scroll fluide (polish) : scrollToEnd() anime contentY au
                // lieu d'un saut — PAS positionViewAtEnd() (méthode ListView,
                // TypeError sur Flickable).
                Behavior on contentY {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }

                ColumnLayout {
                    id: msgCol

                    width: msgList.width
                    spacing: 8

                    Repeater {
                        model: root.messages

                        // ⚠️ Avec ListModel, modelData N'EXISTE PAS (TypeError) :
                        // on utilise model.role / model.text / model.data / model.ts.
                        // Géométrie pilotée par le CONTENU (contentCol), jamais par
                        // l'implicit d'un Rectangle (toujours 0 — bug #2).
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: bubble.height + 8

                            // Bulle user → droite, IA → gauche
                            Rectangle {
                                id: bubble

                                width: Math.min(parent.width * 0.82, contentCol.implicitWidth + 24)
                                height: contentCol.implicitHeight + 16
                                radius: 14
                                color: model.role === "user" ? cUserBubble : (model.role === "img" ? Qt.rgba(0.2, 0.2, 0.3, 0.6) : cAiBubble)
                                anchors.right: model.role === "user" ? parent.right : undefined
                                anchors.left: model.role === "user" ? undefined : parent.left
                                border.color: Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1

                                // top/left/right SANS bottom → la hauteur suit le
                                // contenu (contentCol.implicitHeight) ; anchors.fill
                                // figerait la hauteur sur celle du parent.
                                ColumnLayout {
                                    id: contentCol

                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 12
                                    spacing: 6

                                    Image {
                                        visible: model.role === "img"
                                        source: model.data ? ("data:image/png;base64," + model.data) : ""
                                        Layout.preferredWidth: 180
                                        Layout.preferredHeight: 120
                                        fillMode: Image.PreserveAspectFit
                                        clip: true
                                    }

                                    Text {
                                        visible: model.role === "img"
                                        text: model.text
                                        font.pixelSize: 10
                                        color: cDim
                                    }

                                    Text {
                                        visible: model.role !== "img"
                                        text: model.text || "…"
                                        font.pixelSize: 13
                                        color: model.role === "user" ? "#ffffff" : cText
                                        textFormat: Text.PlainText
                                        wrapMode: Text.Wrap
                                        Layout.fillWidth: true
                                    }

                                    // Horodatage HH:MM — caché pour les bulles
                                    // système/erreur (ts = 0)
                                    Text {
                                        visible: model.ts > 0
                                        text: root.fmtTime(model.ts)
                                        font.pixelSize: 9
                                        color: model.role === "user" ? Qt.rgba(1, 1, 1, 0.55) : cDim
                                        Layout.alignment: model.role === "user" ? Qt.AlignRight : Qt.AlignLeft
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

                    // 📷 Capture : sélection de zone → attachée au prochain message
                    Text {
                        text: "📷"
                        font.pixelSize: 16
                        color: cDim
                        Layout.alignment: Qt.AlignVCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.doCapture()
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }

                    }

                    // TextArea multiligne : Entrée = envoyer, Shift+Entrée = nouvelle
                    // ligne. maximumHeight + wrapMode → grandit jusqu'à 100 px puis
                    // scroll interne (pattern auto-resizing TextArea des apps de chat).
                    TextArea {
                        id: inputField

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.minimumHeight: 32
                        // ⚠️ PAS maximumHeight (n'existe pas sur TextArea) — c'est
                        // Layout.maximumHeight (attached property Layout) qui plafonne
                        // la hauteur dans la RowLayout : le champ grandit avec le
                        // contenu (implicitHeight) jusqu'à 100 px puis scroll interne.
                        Layout.maximumHeight: 100
                        wrapMode: TextEdit.Wrap
                        verticalAlignment: TextEdit.AlignVCenter
                        placeholderText: serverDown ? "serveur hors ligne…" : (modelLoading ? "chargement du modèle…" : "Message à 愛子…")
                        placeholderTextColor: cDim
                        color: cText
                        font.pixelSize: 13

                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (!(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true;
                                    root.sendMessage();
                                }
                            }
                        }

                        background: Rectangle {
                            color: "transparent"
                        }

                    }

                    // ➤ Bouton d'envoi circulaire (visible, hover plus clair, dim quand génération)
                    Rectangle {
                        id: sendBtn

                        property bool sendHover: false

                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        Layout.alignment: Qt.AlignVCenter
                        radius: 15
                        color: generating ? Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.35)
                                         : (sendHover ? Qt.lighter(cAccent, 1.25) : cAccent)
                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "➤"
                            font.pixelSize: 14
                            color: generating ? cDim : "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !generating
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: sendBtn.sendHover = true
                            onExited: sendBtn.sendHover = false
                            onClicked: root.sendMessage()
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
