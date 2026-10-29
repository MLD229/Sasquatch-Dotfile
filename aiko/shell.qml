// shell.qml — 愛子 (Aiko) : sidebar GAUCHE, verre, LLM local éphémère.
// Lancement : ~/.config/aiko/aiko.sh  (Super+N)
//
// CONTRAT DE CYCLE DE VIE (le cœur du sujet)
//   ouverture  → rien de lourd : ce QML + server.py (<40 Mo). Modèle déchargé.
//   1er message→ POST /api/chat ; le backend lance llama-server, attend
//                /health, puis streame. L'UI affiche « chargement du modèle… ».
//   fermeture  → POST /api/shutdown : llama-server tué (SIGTERM → SIGKILL),
//                historique RAM jeté, backend sorti. pgrep llama-server = 0.
//   inactivité → le backend tue llama-server après 5 min (réglable).
//
// STYLE : identité cc/sidebar — mêmes tokens glass*, BackgroundEffect
// (ext-background-effect-v1), palette relue sur /api/palette. Ancrage GAUCHE,
// 420 px, exclusiveZone 0 (overlay : ne pousse aucune fenêtre).
//
// AUCUN GRAB CLAVIER : pas de HyprlandFocusGrab. Le panneau demande le focus
// au compositeur (OnDemand) mais ne le CAPTURE jamais — sinon hyprlock ne
// reçoit plus le mot de passe (déjà vécu).
//
// RIEN DE LA CONVERSATION N'EST CONSERVÉ : l'historique vit dans la ListModel
// `msgs` et dans la RAM du backend ; il disparaît à la fermeture.
// SEULE exception (demande explicite) : le choix 3B/7B, écrit dans
// ~/.local/state/aiko/prefs.json au clic et relu au démarrage. C'est une
// préférence d'affichage, pas une mémoire de conversation.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "qml"

PanelWindow {
    id: root

    // ── Palette : valeurs de secours = cc/qml/Palette.qml ────────────────
    property color cBg: "#181529"
    property color cBgSolid: "#181529"
    property color cCard: "#251f36"
    property color cText: "#d1cfd9"
    property color cTextDim: "#7d7b89"
    property color cAccent: "#87709b"
    property color cAccent2: "#87709b"
    property color cOverlay: "#99021933"
    property color cGood: "#a6e3a1"
    property color cWarn: "#f9e2af"
    property color cHot: "#f38ba8"

    readonly property string apiBase: "http://127.0.0.1:"
                                      + (Quickshell.env("AIKO_PORT") || "8791")

    // ── Tokens « verre » (identiques à cc/sidebar) ───────────────────────
    function shade(c, k) {
        return k >= 1 ? Qt.lighter(c, k) : Qt.darker(c, 1 / k);
    }
    function rgba(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    function mixN(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t,
                       a.g * (1 - t) + b.g * t,
                       a.b * (1 - t) + b.b * t, 1.0);
    }
    function glassTint(c, t, a) {
        var m = root.mixN(c, root.cText, t);
        return Qt.rgba(m.r, m.g, m.b, a);
    }

    readonly property color accentLift: root.mixN(root.cAccent, root.cText, 0.30)
    readonly property color glassBg: root.glassTint(root.cBgSolid, 0.10, 0.36)
    readonly property color glassBgDeep: root.glassTint(Qt.darker(root.cBgSolid, 1.25), 0.05, 0.46)
    readonly property color glassCard: root.glassTint(root.cCard, 0.17, 0.24)
    readonly property color glassInset: root.glassTint(Qt.darker(root.cBg, 1.4), 0.04, 0.50)
    readonly property color glassBtn: root.glassTint(Qt.darker(root.cCard, 1.75), 0.07, 0.62)
    readonly property color glassBorder: root.rgba(root.accentLift, 0.30)
    readonly property color glassHighlight: root.rgba(root.cText, 0.12)
    readonly property color glassShadow: root.rgba(root.cOverlay, 0.45)

    // ── Fenêtre : ancrée À GAUCHE, overlay ──────────────────────────────
    anchors {
        top: true
        bottom: true
        left: true
    }
    margins {
        top: 8           // la layer-shell « top » commence déjà sous la waybar
        bottom: 10
        left: 10
    }
    implicitWidth: 420
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: true
    WlrLayershell.namespace: "aiko"
    // OnDemand : le panneau peut recevoir le clavier sans le VERROUILLER.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    BackgroundEffect.blurRegion: Region {
        item: sheet
        radius: 9
    }

    // ── État UI ──────────────────────────────────────────────────────────
    property bool opened: false
    property string engine: "idle"         // idle | loading | ready | error
    property string profile: "rapide"
    property string profileLabel: "3B"
    property real tokS: 0
    property int vram: 0
    property int coldMs: 0
    property int firstMs: 0
    property bool streaming: false
    property bool injectContext: false
    property string errMsg: ""
    property string notice: ""
    property bool binWarned: false
    property bool follow: true
    property var chat: null
    property int cursor: 0
    property string pendingLine: ""
    property real tStart: 0
    property int tokCount: 0
    // Trace stdout (quickshell) quand AIKO_DEBUG=1 : prouve le streaming côté UI.
    readonly property bool dbg: Quickshell.env("AIKO_DEBUG") === "1"

    readonly property bool busy: root.streaming
    readonly property string stateText: {
        if (root.engine === "loading")
            return "chargement du modèle…";
        if (root.engine === "ready")
            return "prêt · " + root.profileLabel
                   + (root.tokS > 0 ? " · " + root.tokS.toFixed(1) + " tok/s" : "")
                   + " · VRAM " + (root.vram / 1024).toFixed(2) + " Go";
        if (root.engine === "error")
            return "erreur moteur";
        return "modèle déchargé · 0 process";
    }
    readonly property color stateColor: root.engine === "ready" ? root.cGood
                                     : root.engine === "loading" ? root.cWarn
                                     : root.engine === "error" ? root.cHot
                                     : root.cTextDim

    // ── Messages : ListModel = RAM seule, perdue à la fermeture ──────────
    ListModel {
        id: msgs
    }

    // ── HTTP ─────────────────────────────────────────────────────────────
    function api(method, path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 6000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                data = null;
            }
            if (cb)
                cb(data, xhr.status);
        };
        xhr.open(method, root.apiBase + path);
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body !== null ? JSON.stringify(body) : null);
    }

    function post(path, body, cb) {
        root.api("POST", path, body || {}, cb);
    }

    function refreshPalette() {
        root.api("GET", "/api/palette", null, function (p) {
            if (!p || !p.bg)
                return;
            root.cBg = p.bg || root.cBg;
            root.cBgSolid = p.bgSolid || root.cBgSolid;
            root.cCard = p.card || root.cCard;
            root.cText = p.text || root.cText;
            root.cTextDim = p.textDim || root.cTextDim;
            root.cAccent = p.accent || root.cAccent;
            root.cAccent2 = p.accent2 || root.cAccent2;
            root.cOverlay = p.overlay || root.cOverlay;
            root.cGood = p.good || root.cGood;
            root.cWarn = p.warn || root.cWarn;
            root.cHot = p.hot || root.cHot;
        });
    }

    function refreshState() {
        root.api("GET", "/api/state", null, function (s) {
            if (!s || s.state === undefined) {
                root.engine = "idle";
                return;
            }
            if (!root.streaming)
                root.engine = s.state;
            // Modèle chargé → son profil ; sinon la PRÉFÉRENCE mémorisée
            // (prefs.json), pour que l'UI rouvre sur le dernier choix 3B/7B.
            var prof = s.profile || s.profile_pref;
            if (prof) {
                root.profile = prof;
                root.profileLabel = (s.profiles && s.profiles[prof])
                                    || (prof === "best" ? "7B" : "3B");
            }
            if (!root.binWarned && s.binary === null) {
                root.binWarned = true;
                root.errMsg = "llama-server introuvable — lancer "
                              + "~/.config/aiko/installer.sh";
            }
            root.vram = s.vram_mib || 0;
            if (typeof s.tok_s === "number")
                root.tokS = s.tok_s;
        });
    }

    // ── Découpage d'un message en texte / blocs ```bash``` ───────────────
    function segments(t) {
        var out = [];
        var i = 0;
        if (!t)
            return out;
        while (i < t.length) {
            var s = t.indexOf("```", i);
            if (s < 0) {
                out.push({ "code": false, "body": t.substring(i) });
                break;
            }
            if (s > i)
                out.push({ "code": false, "body": t.substring(i, s) });
            var e = t.indexOf("```", s + 3);
            var body = e < 0 ? t.substring(s + 3) : t.substring(s + 3, e);
            body = body.replace(/^[a-zA-Z0-9_+.-]*\r?\n/, "");
            out.push({ "code": true, "body": body.replace(/\s+$/, ""),
                       "open": e < 0 });
            if (e < 0)
                break;
            i = e + 3;
        }
        return out;
    }

    // ── Envoi + streaming NDJSON ─────────────────────────────────────────
    function send() {
        var text = input.text.trim();
        if (!text || root.streaming)
            return;
        msgs.append({ "role": "user", "text": text, "meta": "" });
        msgs.append({ "role": "assistant", "text": "", "meta": "…" });
        input.text = "";
        root.errMsg = "";
        root.notice = "";
        root.streaming = true;
        root.follow = true;
        root.cursor = 0;
        root.pendingLine = "";
        root.tokS = 0;
        root.tokCount = 0;
        root.tStart = Date.now();
        var xhr = new XMLHttpRequest();
        root.chat = xhr;
        xhr.open("POST", root.apiBase + "/api/chat");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 0;      // cold start possible : pas de coupure côté client
        xhr.send(JSON.stringify({
            "text": text,
            "profile": root.profile,
            "inject_context": root.injectContext
        }));
        streamPoll.restart();
    }

    function handleEvent(line) {
        var obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        var last = msgs.count - 1;
        if (obj.e === "status") {
            root.engine = "loading";
            root.notice = obj.text || "chargement du modèle…";
        } else if (obj.e === "ready") {
            root.engine = "ready";
            root.notice = "";
            root.profileLabel = obj.label || root.profileLabel;
            root.coldMs = obj.cold_start_ms || 0;
            root.firstMs = obj.first_token_ms || 0;
            root.vram = obj.vram_mib || root.vram;
        } else if (obj.e === "token") {
            if (last >= 0)
                msgs.setProperty(last, "text", msgs.get(last).text + obj.t);
            root.tokCount += 1;
            if (root.dbg && (root.tokCount === 1 || root.tokCount % 10 === 0))
                console.log("[aiko-ui] token", root.tokCount, "+",
                            (Date.now() - root.tStart) + "ms");
        } else if (obj.e === "done") {
            if (root.dbg)
                console.log("[aiko-ui] done tokens=" + obj.tokens
                            + " tok_s=" + obj.tok_s + " ui_msgs=" + msgs.count
                            + " total=" + (Date.now() - root.tStart) + "ms");
            root.tokS = obj.tok_s || 0;
            root.engine = "ready";
            root.vram = root.vram;
            if (last >= 0) {
                var bits = [];
                if (obj.tokens)
                    bits.push(obj.tokens + " tokens");
                if (obj.tok_s)
                    bits.push(obj.tok_s.toFixed(1) + " tok/s");
                if (obj.first_token_ms)
                    bits.push("1er token " + (obj.first_token_ms / 1000).toFixed(1) + " s");
                msgs.setProperty(last, "meta", obj.stopped ? "interrompu" : bits.join(" · "));
            }
        } else if (obj.e === "error") {
            root.errMsg = obj.message || "erreur";
            root.engine = "error";
            if (last >= 0 && msgs.get(last).text.length === 0)
                msgs.remove(last);
        }
    }

    function pump() {
        var xhr = root.chat;
        if (!xhr)
            return;
        var all = "";
        try {
            all = xhr.responseText || "";
        } catch (e) {
            all = "";
        }
        if (all.length > root.cursor) {
            var chunk = all.substring(root.cursor);
            root.cursor = all.length;
            var buf = root.pendingLine + chunk;
            var lines = buf.split("\n");
            root.pendingLine = lines.pop();
            for (var i = 0; i < lines.length; ++i) {
                var l = lines[i].trim();
                if (l.length > 0)
                    root.handleEvent(l);
            }
        }
        if (xhr.readyState === 4) {
            streamPoll.stop();
            if (root.pendingLine.trim().length > 0)
                root.handleEvent(root.pendingLine.trim());
            root.pendingLine = "";
            root.chat = null;
            root.streaming = false;
            var last = msgs.count - 1;
            if (last >= 0 && msgs.get(last).text.length === 0
                    && msgs.get(last).role === "assistant" && !root.errMsg)
                msgs.setProperty(last, "meta", "pas de réponse");
        }
    }

    function stopGeneration() {
        root.post("/api/stop", {});
        if (root.chat) {
            try {
                root.chat.abort();
            } catch (e) {
                // rien : la lecture s'arrête d'elle-même
            }
        }
        streamPoll.stop();
        root.streaming = false;
        var last = msgs.count - 1;
        if (last >= 0 && msgs.get(last).role === "assistant")
            msgs.setProperty(last, "meta", "interrompu");
    }

    function newConversation() {
        if (root.streaming)
            root.stopGeneration();
        root.post("/api/new", {});
        msgs.clear();
        root.notice = "";
        root.errMsg = "";
        root.tokS = 0;
    }

    function setProfile(p) {
        if (root.streaming)
            return;
        root.profile = p;
        root.profileLabel = (p === "best" ? "7B" : "3B");
        root.post("/api/model", { "profile": p }, function (r, code) {
            if (!r || r.ok !== true) {
                root.errMsg = (r && r.error) || ("changement de modèle refusé ("
                                                 + code + ")");
                return;
            }
            root.errMsg = "";
            root.engine = "idle";
            root.vram = 0;
            root.tokS = 0;
            // « persisté » : le choix est relu au prochain démarrage (prefs.json).
            root.notice = "modèle « " + p + " » (" + root.profileLabel + ")"
                          + (r.persisted ? " mémorisé" : " non mémorisé (disque ?)")
                          + " — chargé au prochain message";
            noticeTimer.restart();
        });
    }

    function copy(text) {
        copier.command = ["wl-copy", text];
        copier.running = true;
        root.notice = "commande copiée — colle-la toi-même dans kitty";
        noticeTimer.restart();
    }

    // ── Fermeture : tuer le modèle, jeter l'historique, sortir ──────────
    function close() {
        if (!root.opened)
            return;
        root.opened = false;
        if (root.chat) {
            try {
                root.chat.abort();
            } catch (e) {
                // déjà terminé
            }
        }
        // Le backend tue llama-server, vide la RAM, puis sort lui aussi.
        root.post("/api/shutdown", {});
        quitTimer.restart();
    }

    // ── Timers ───────────────────────────────────────────────────────────
    Timer {
        id: openTimer

        interval: 40
        running: false
        onTriggered: {
            root.opened = true;
            input.forceActiveFocus();
        }
    }
    Timer {
        id: quitTimer

        interval: 260
        running: false
        onTriggered: Qt.quit()
    }
    Timer {
        id: streamPoll

        interval: 50
        repeat: true
        running: false
        onTriggered: root.pump()
    }
    Timer {
        id: stateTimer

        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (!root.streaming)
                root.refreshState();
        }
    }
    Timer {
        id: paletteTimer

        interval: 4000
        repeat: true
        running: true
        onTriggered: root.refreshPalette()
    }
    Timer {
        id: noticeTimer

        interval: 3500
        running: false
        onTriggered: root.notice = ""
    }

    // Focus demandé, JAMAIS capturé (pas de grab clavier).
    Shortcut {
        sequence: "Escape"
        onActivated: root.close()
    }
    Shortcut {
        sequences: ["Ctrl+N"]
        onActivated: root.newConversation()
    }

    Process {
        id: copier

        // argv direct : aucun shell, donc aucun risque d'interprétation.
        command: ["wl-copy", ""]
        running: false
    }

    Component.onCompleted: {
        root.refreshPalette();
        root.refreshState();
        // Note technique (pas dans l'UI) : préférence ignorée → repli sur le défaut.
        root.api("GET", "/api/state", null, function (s) {
            if (s && s.pref_note)
                console.log("[aiko-ui] préférence ignorée :", s.pref_note);
            if (s && s.profile_pref)
                console.log("[aiko-ui] modèle mémorisé :", s.profile_pref,
                            "(préférence seule, conversation volatile)");
        });
        openTimer.start();
    }

    // ── Feuille ──────────────────────────────────────────────────────────
    Rectangle {
        id: sheetShadow

        x: sheet.x + 2
        y: sheet.y + 10
        width: sheet.width - 4
        height: sheet.height - 12
        radius: 22
        color: root.glassShadow
        opacity: sheet.opacity * 0.9
    }

    Rectangle {
        id: sheet

        width: root.width
        height: root.height
        x: root.opened ? 0 : -root.width - 6
        radius: 20
        border.width: 1
        border.color: root.glassBorder
        clip: true

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.glassBg
            }
            GradientStop {
                position: 1.0
                color: root.glassBgDeep
            }
        }

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        opacity: root.opened ? 1.0 : 0.0

        // liseré lumineux du haut
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 1
            color: root.glassHighlight
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // ── En-tête ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: "愛子"
                        color: root.cText
                        font.pixelSize: 19
                        font.bold: true
                        font.letterSpacing: 3
                    }
                    Text {
                        text: "aiko · local · conversation non gardée"
                        color: root.cTextDim
                        font.pixelSize: 9
                        font.letterSpacing: 1.2
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                GlassButton {
                    glyph: "✕"
                    hint: "fermer (Échap) — décharge le modèle"
                    baseColor: root.glassBtn
                    accentColor: root.cHot
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    compact: true
                    onClicked: root.close()
                }
            }

            // ── Ligne d'état moteur ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: root.stateColor

                    SequentialAnimation on opacity {
                        running: root.engine === "loading"
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.25
                            duration: 500
                        }
                        NumberAnimation {
                            to: 1.0
                            duration: 500
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.stateText
                    color: root.stateColor
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text {
                    visible: root.firstMs > 0 && root.engine === "ready"
                    text: "cold " + (root.coldMs / 1000).toFixed(1) + " s"
                    color: root.cTextDim
                    font.pixelSize: 9
                }
            }

            // ── Barre de contrôle ───────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                GlassButton {
                    glyph: "⚡"
                    label: "3B"
                    on: root.profile === "rapide"
                    hint: "Qwen2.5-3B Q4_K_M — rapide, ~1.9 Go"
                    baseColor: root.glassBtn
                    accentColor: root.accentLift
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    compact: true
                    onClicked: root.setProfile("rapide")
                }
                GlassButton {
                    glyph: "◆"
                    label: "7B"
                    on: root.profile === "best"
                    hint: "Qwen2.5-7B Q4_K_M — meilleur, ~4.7 Go (marge VRAM faible)"
                    baseColor: root.glassBtn
                    accentColor: root.accentLift
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    compact: true
                    onClicked: root.setProfile("best")
                }

                Item {
                    Layout.fillWidth: true
                }

                GlassButton {
                    glyph: "⌘"
                    label: "contexte"
                    on: root.injectContext
                    hint: "joint un digest statique des chemins du dotfile"
                    baseColor: root.glassBtn
                    accentColor: root.accentLift
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    compact: true
                    onClicked: {
                        root.injectContext = !root.injectContext;
                        root.notice = root.injectContext
                            ? "contexte dotfile joint au prochain message"
                            : "contexte retiré";
                        noticeTimer.restart();
                    }
                }
                GlassButton {
                    glyph: "＋"
                    label: "neuf"
                    hint: "vider l'historique RAM (Ctrl+N)"
                    baseColor: root.glassBtn
                    accentColor: root.accentLift
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    compact: true
                    onClicked: root.newConversation()
                }
            }

            // ── Fil de messages ─────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list

                    anchors.fill: parent
                    clip: true
                    spacing: 8
                    model: msgs
                    boundsBehavior: Flickable.StopAtBounds
                    onAtYEndChanged: root.follow = atYEnd
                    onCountChanged: if (root.follow)
                        list.positionViewAtEnd()

                    delegate: Item {
                        id: msgRow

                        required property int index
                        required property string role
                        required property string text
                        required property string meta

                        width: list.width
                        implicitHeight: bubble.implicitHeight + 2

                        Rectangle {
                            id: bubble

                            readonly property bool isUser: msgRow.role === "user"
                            readonly property var segs: root.segments(msgRow.text)
                            readonly property bool lastOne: msgRow.index === msgs.count - 1

                            width: Math.min(list.width - 6,
                                            isUser ? list.width * 0.86 : list.width)
                            x: isUser ? parent.width - width : 0
                            implicitHeight: body.implicitHeight + 20
                            radius: 12
                            color: isUser ? root.rgba(root.accentLift, 0.18) : root.glassCard
                            border.width: 1
                            border.color: isUser ? root.rgba(root.accentLift, 0.35)
                                                 : root.rgba(root.cText, 0.08)

                            Column {
                                id: body

                                x: 10
                                y: 9
                                width: parent.width - 20
                                spacing: 6

                                Repeater {
                                    model: bubble.segs

                                    delegate: Column {
                                        id: segCol

                                        required property var modelData
                                        width: body.width
                                        spacing: 4

                                        // bloc de commande
                                        Rectangle {
                                            visible: segCol.modelData.code === true
                                            width: parent.width
                                            height: visible ? codeCol.implicitHeight + 14 : 0
                                            radius: 8
                                            color: root.glassInset
                                            border.width: 1
                                            border.color: root.rgba(root.cText, 0.10)

                                            Column {
                                                id: codeCol

                                                x: 9
                                                y: 7
                                                width: parent.width - 18
                                                spacing: 4

                                                Text {
                                                    width: parent.width
                                                    text: segCol.modelData.body
                                                    color: root.cGood
                                                    font.family: "JetBrainsMono Nerd Font, monospace"
                                                    font.pixelSize: 11
                                                    wrapMode: Text.WrapAnywhere
                                                    textFormat: Text.PlainText
                                                }
                                                Row {
                                                    spacing: 6

                                                    GlassButton {
                                                        // pas de copie d'une commande encore en
                                                        // train d'arriver (``` non refermé)
                                                        visible: segCol.modelData.open !== true
                                                        glyph: "⧉"
                                                        label: "copier"
                                                        hint: "copie dans le presse-papier (jamais d'exécution)"
                                                        baseColor: root.glassBtn
                                                        accentColor: root.accentLift
                                                        fgText: root.cText
                                                        fgDim: root.cTextDim
                                                        borderColor: root.glassBorder
                                                        compact: true
                                                        onClicked: root.copy(segCol.modelData.body)
                                                    }
                                                }
                                            }
                                        }

                                        // texte courant
                                        Text {
                                            visible: segCol.modelData.code !== true
                                            width: parent.width
                                            text: (segCol.modelData.body || "")
                                                  + (root.streaming && bubble.lastOne
                                                     && bubble.isUser === false
                                                     && segCol.index === bubble.segs.length - 1
                                                     ? "▍" : "")
                                            color: root.cText
                                            font.pixelSize: 12
                                            lineHeight: 1.15
                                            wrapMode: Text.Wrap
                                            textFormat: Text.PlainText
                                        }
                                    }
                                }

                                Text {
                                    visible: msgRow.meta.length > 0
                                    width: parent.width
                                    text: msgRow.meta
                                    color: root.cTextDim
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // État vide
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    spacing: 8
                    visible: msgs.count === 0

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Demande une commande,\nou une question courte."
                        color: root.cTextDim
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: ["lister les fenêtres Hyprland",
                                "capture d'écran de la fenêtre active",
                                "changer le gap entre fenêtres"]

                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width
                            height: 28
                            radius: 8
                            color: hover.containsMouse
                                   ? root.rgba(root.accentLift, 0.16) : root.glassCard
                            border.width: 1
                            border.color: root.rgba(root.cText, 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: root.cTextDim
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: hover

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    input.text = parent.modelData;
                                    input.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // ── Avis / erreur ───────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                visible: root.errMsg.length > 0
                text: root.errMsg
                color: root.cHot
                font.pixelSize: 10
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: root.notice.length > 0
                text: root.notice
                color: root.cWarn
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // ── Saisie ──────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: input.height + 16
                radius: 10
                color: root.glassInset
                border.width: 1
                border.color: input.activeFocus ? root.rgba(root.accentLift, 0.55)
                                                : root.rgba(root.cText, 0.10)

                TextArea {
                    id: input

                    x: 9
                    y: 8
                    width: parent.width - 18
                    height: Math.min(84, Math.max(20, contentHeight))
                    placeholderText: "demande une commande ou une explication…"
                    placeholderTextColor: root.cTextDim
                    color: root.cText
                    font.pixelSize: 12
                    wrapMode: TextArea.Wrap
                    background: null
                    selectByMouse: true
                    focus: true

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (event.modifiers & Qt.ShiftModifier)
                                return;    // Shift+Entrée = nouvelle ligne
                            root.send();
                            event.accepted = true;
                        }
                    }
                }
            }

            // ── Actions + rappel « rien n'est conservé » ────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                GlassButton {
                    glyph: root.streaming ? "■" : "↵"
                    label: root.streaming ? "stop" : "envoyer"
                    on: root.streaming
                    hint: root.streaming ? "interrompt la génération" : "envoyer (Entrée)"
                    baseColor: root.glassBtn
                    accentColor: root.streaming ? root.cHot : root.accentLift
                    fgText: root.cText
                    fgDim: root.cTextDim
                    borderColor: root.glassBorder
                    onClicked: root.streaming ? root.stopGeneration() : root.send()
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: "conversation non conservée ✦"
                    color: root.cTextDim
                    font.pixelSize: 9
                    font.letterSpacing: 0.6
                }
            }
        }
    }

    // ── Hook de test : AIKO_DEMO=1 envoie un message tout seul ──────────
    Timer {
        interval: 1400
        running: Quickshell.env("AIKO_DEMO") === "1"
        repeat: false
        onTriggered: {
            input.text = Quickshell.env("AIKO_DEMO_TEXT")
                         || "Donne la commande pour recharger Hyprland, puis une ligne d'explication.";
            root.send();
        }
    }
}
