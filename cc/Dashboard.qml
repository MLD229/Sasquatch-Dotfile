// Dashboard.qml — page d'accueil du CC (façon capture de référence).
// Trois colonnes : profil système · mises à jour + calendrier · horloge/météo + tâches.
// Toutes les couleurs viennent de la palette du CC (aucun hex en dur) ; toutes les
// données viennent du backend (sysinfo / updates / weather / tasks).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: dash

    property color cCard: "#181825"
    property color cText: "#cdd6f4"
    property color cTextDim: "#a6adc8"
    property color cAccent: "#89b4fa"
    property color cAccent2: "#94e2d5"
    property color cWarn: "#f9e2af"
    property color cGood: "#a6e3a1"
    property color cHot: "#f38ba8"

    property var sys: ({})
    property var upd: ({})
    property var wx: ({})
    property var tasks: ({items: [], total: 0, done: 0})
    property string newTask: ""

    // ── Lecteur musique ───────────────────────────────────────────────
    // Les DONNÉES viennent de main.qml (un seul poller /api/music/status à
    // 1 s pour tout le CC) ; les ACTIONS remontent par le signal musicCmd
    // → root.api. Aucun timer ni abonnement dupliqué ici.
    property var music: ({})
    property var sysVol: ({volume: 0, muted: false})
    property var vizVals: []
    signal musicCmd(string path, var body)

    readonly property bool isPlaying: !!(dash.music && dash.music.playing)
    // Carte complète seulement quand ça joue ; sinon compacte (pas de vide).
    readonly property bool musicExpanded: dash.isPlaying
    readonly property string artUrl: (dash.music && dash.music.art)
                                      ? "http://127.0.0.1:8765" + dash.music.art : ""
    readonly property string trackTitle: (dash.music && dash.music.title)
                                         ? dash.music.title : "Aucune musique en cours"
    readonly property string trackArtist: (dash.music && dash.music.artist) ? dash.music.artist : ""

    function mmss(s) {
        s = Math.max(0, Math.round(s || 0));
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }

    // Heure locale, rafraîchie chaque seconde.
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: dash.now = new Date() }

    function api(path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.timeout = 4000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try { cb(JSON.parse(xhr.responseText)); } catch (e) { cb({}); }
        };
        xhr.open(body ? "POST" : "GET", "http://127.0.0.1:8765" + path);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body ? JSON.stringify(body) : null);
    }

    function refresh() {
        api("/api/sysinfo", null, function(d) { dash.sys = d || {}; });
        api("/api/updates", null, function(d) { dash.upd = d || {}; });
        api("/api/weather?city=Lyon", null, function(d) { dash.wx = d || {}; });
        api("/api/tasks", null, function(d) { dash.tasks = d || {items: []}; });
    }
    Component.onCompleted: refresh()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: dash.refresh() }

    function salutation(h) {
        if (h < 6) return "Bonne nuit";
        if (h < 12) return "Bonjour";
        if (h < 18) return "Bon après-midi";
        return "Bonsoir";
    }
    function deux(n) { return (n < 10 ? "0" : "") + n; }
    function heure() { return deux(dash.now.getHours()) + ":" + deux(dash.now.getMinutes()); }

    // ---- Calendrier (pur QML, aucune dépendance) ----
    property int calMonth: dash.now.getMonth()
    property int calYear: dash.now.getFullYear()
    readonly property var mois: ["janvier", "février", "mars", "avril", "mai", "juin",
                                "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    readonly property var jours: ["L", "M", "M", "J", "V", "S", "D"]
    function premierJour(m, y) {          // 0 = lundi
        var d = new Date(y, m, 1).getDay();
        return (d + 6) % 7;
    }
    function joursDansMois(m, y) { return new Date(y, m + 1, 0).getDate(); }
    function changeMois(delta) {
        var m = dash.calMonth + delta, y = dash.calYear;
        if (m < 0) { m = 11; y--; }
        if (m > 11) { m = 0; y++; }
        dash.calMonth = m; dash.calYear = y;
    }

    // Carte translucide de base.
    component Carte: Rectangle {
        id: carte
        property string titre: ""
        radius: 16
        // Hauteur naturelle = contenu (marges internes 14 comprises) : une
        // carte peut donc s'auto-dimensionner sans hauteur magique.
        implicitHeight: inner.implicitHeight + 28
        color: Qt.rgba(dash.cCard.r, dash.cCard.g, dash.cCard.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.06)
        default property alias contenu: inner.data
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            // Le titre fait partie de la colonne (avant, il était ancré
            // par-dessus le contenu et chevauchait la 1re ligne des cartes
            // « calendrier » et « musique »). Invisible → ne prend pas de place.
            Text {
                text: carte.titre
                visible: text.length > 0
                font.pixelSize: 10
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
                color: dash.cTextDim
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 14

        // ═════════ COLONNE 1 : profil ═════════
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.round(dash.width * 0.36)
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: dash.salutation(dash.sys.hour !== undefined ? dash.sys.hour : dash.now.getHours())
                    font.pixelSize: 13
                    color: dash.cTextDim
                }
                Text {
                    text: "allumé depuis • " + (dash.sys.uptime || "…")
                    font.pixelSize: 22
                    font.bold: true
                    color: dash.cText
                }
            }

            Carte {
                titre: "PROFIL"
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        width: 56; height: 56; radius: 28
                        color: Qt.rgba(dash.cAccent.r, dash.cAccent.g, dash.cAccent.b, 0.22)
                        Text {
                            anchors.centerIn: parent
                            text: (dash.sys.user || "?").substring(0, 1).toUpperCase()
                            font.pixelSize: 24; font.bold: true; color: dash.cText
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: dash.sys.user || "…"; font.pixelSize: 16; font.bold: true; color: dash.cText }
                        Text {
                            text: (dash.sys.user || "") + "@" + (dash.sys.host || "")
                            font.pixelSize: 11; color: dash.cTextDim
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.10)
                }

                // 5 lignes : distribution, CPU, GPU, noyau, shell
                Repeater {
                    model: [
                        { g: "", k: "Système", v: dash.sys.distro || "…" },
                        { g: "", k: "CPU", v: (dash.sys.cpu || "…") + (dash.sys.cores ? "  ·  " + dash.sys.cores + " cœurs" : "") },
                        { g: "", k: "GPU", v: dash.sys.gpu || "—" },
                        { g: "", k: "Noyau", v: dash.sys.kernel || "…" },
                        { g: "", k: "Shell", v: dash.sys.shell || "…" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            width: 26; height: 26; radius: 8
                            color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.06)
                            Text {
                                anchors.centerIn: parent
                                text: modelData.k.substring(0, 1)
                                font.pixelSize: 11; color: dash.cTextDim
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { text: modelData.k; font.pixelSize: 10; color: dash.cTextDim }
                            Text {
                                text: modelData.v
                                font.pixelSize: 12; color: dash.cText
                                elide: Text.ElideRight
                                Layout.maximumWidth: dash.width * 0.30
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // ═════════ MUSIQUE (déplacée de la page « Système ») ═════════
            // Pochette · titre/artiste/album · prev/play/stop/next · timeline
            // (seek) · volume système · visualiseur. Compacte quand rien ne
            // joue : seuls la pochette, le titre et 3 boutons restent.
            Carte {
                titre: "MUSIQUE"
                Layout.fillWidth: true

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: dash.musicExpanded ? 76 : 42
                        Layout.preferredHeight: dash.musicExpanded ? 76 : 42
                        radius: 10
                        clip: true
                        color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.06)
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // Clé de cache = la piste, PAS l'heure : le statut
                            // est re-pollé chaque seconde, une URL datée
                            // re-téléchargerait la pochette en boucle.
                            cache: false
                            source: dash.artUrl
                            visible: dash.artUrl !== ""
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "🎵"
                            font.pixelSize: dash.musicExpanded ? 26 : 16
                            color: dash.cTextDim
                            visible: dash.artUrl === ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        // preferred 0 + minimum 0 : la colonne se contente de
                        // la place restante au lieu de pousser le contenu
                        // (la durée/le % débordaient hors de la carte).
                        Layout.preferredWidth: 0
                        Layout.minimumWidth: 0
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            // minimum 0 = peut rétrécir (elide) au lieu
                            // d'imposer sa largeur au parent
                            Layout.minimumWidth: 0
                            text: dash.trackTitle
                            font.pixelSize: 13
                            font.bold: true
                            color: dash.cText
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: text.length > 0
                            text: dash.trackArtist
                            font.pixelSize: 11
                            color: dash.cTextDim
                            elide: Text.ElideRight
                        }
                        // Album + source (navigateur YouTube, MPD…) sur UNE ligne :
                        // deux lignes séparées coûtaient 15 px de haut, pris sur
                        // la carte PROFIL (elle passait sous son bord).
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: dash.musicExpanded && text.length > 0
                            text: {
                                var a = (dash.music && dash.music.album) ? dash.music.album : "";
                                var src = (dash.music && (dash.music.source === "mpris"
                                                          || dash.music.source === "web"))
                                          ? "via " + (dash.music.player ? dash.music.player : "navigateur")
                                          : "";
                                if (a && src) return a + " · " + src;
                                return a || src;
                            }
                            font.pixelSize: 9
                            color: dash.cTextDim
                            elide: Text.ElideRight
                        }

                        // ── Barre de progression (seek au clic) ──
                        RowLayout {
                            Layout.fillWidth: true
                            visible: dash.musicExpanded
                            spacing: 6
                            Text {
                                text: dash.mmss(dash.music ? dash.music.elapsed : 0)
                                font.pixelSize: 9; color: dash.cTextDim
                            }
                            Rectangle {
                                id: musicBar
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.10)
                                Rectangle {
                                    radius: 3
                                    height: parent.height
                                    color: dash.cAccent
                                    width: {
                                        var d = (dash.music && dash.music.duration) ? dash.music.duration : 0;
                                        var e = (dash.music && dash.music.elapsed) ? dash.music.elapsed : 0;
                                        return d > 0 ? musicBar.width * Math.min(1, e / d) : 0;
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: function(mouse) {
                                        var d = (dash.music && dash.music.duration) ? dash.music.duration : 0;
                                        if (d <= 0) return;
                                        dash.musicCmd("/api/music/seek",
                                                      ({pos: Math.round((mouse.x / width) * d)}));
                                    }
                                }
                            }
                            Text {
                                text: dash.mmss(dash.music ? dash.music.duration : 0)
                                font.pixelSize: 9; color: dash.cTextDim
                            }
                        }

                        // ── Commandes + visualiseur ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            IconButtonMini {
                                glyph: "📃"
                                size: 22
                                visible: dash.musicExpanded
                                onClicked: dash.musicCmd("/api/playlist/open", null)
                            }
                            IconButtonMini {
                                glyph: "⏮"
                                size: dash.musicExpanded ? 28 : 26
                                onClicked: dash.musicCmd("/api/music/prev", null)
                            }
                            IconButtonMini {
                                glyph: dash.isPlaying ? "⏸" : "▶"
                                size: dash.musicExpanded ? 32 : 28
                                onClicked: dash.musicCmd("/api/music/toggle", null)
                            }
                            IconButtonMini {
                                glyph: "⏹"
                                size: 26
                                visible: dash.musicExpanded
                                onClicked: dash.musicCmd("/api/music/stop", null)
                            }
                            IconButtonMini {
                                glyph: "⏭"
                                size: dash.musicExpanded ? 28 : 26
                                onClicked: dash.musicCmd("/api/music/next", null)
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // ── Volume système (la sidebar garde la barre épaisse) ──
                        RowLayout {
                            Layout.fillWidth: true
                            visible: dash.musicExpanded
                            spacing: 8
                            IconButtonMini {
                                glyph: (dash.sysVol && dash.sysVol.muted) ? "🔇" : "🔊"
                                size: 22
                                onClicked: dash.musicCmd("/api/system/volume",
                                                         ({mute: !(dash.sysVol && dash.sysVol.muted)}))
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.10)
                                Rectangle {
                                    radius: 3
                                    height: parent.height
                                    color: dash.cAccent2
                                    width: parent.width * ((dash.sysVol && dash.sysVol.volume)
                                                           ? dash.sysVol.volume / 100 : 0)
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: function(mouse) {
                                        var ratio = Math.max(0, Math.min(1, mouse.x / width));
                                        dash.musicCmd("/api/system/volume",
                                                      ({v: Math.round(ratio * 100)}));
                                    }
                                }
                            }
                            Text {
                                text: (dash.sysVol && dash.sysVol.volume ? Math.round(dash.sysVol.volume) : 0) + "%"
                                font.pixelSize: 9
                                color: dash.cTextDim
                            }

                            // Visualiseur cava : données déjà pollées par
                            // main.qml (/api/viz), aucune requête ici.
                            RowLayout {
                                spacing: 2
                                Layout.preferredHeight: 18
                                Layout.alignment: Qt.AlignBottom
                                Repeater {
                                    model: 12
                                    delegate: Rectangle {
                                        Layout.preferredWidth: 3
                                        Layout.preferredHeight: {
                                            var v = (dash.vizVals && dash.vizVals.length > index)
                                                    ? dash.vizVals[index] : 0;
                                            return Math.max(2, v * 18);
                                        }
                                        Layout.alignment: Qt.AlignBottom
                                        radius: 1
                                        color: dash.cAccent
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ═════════ COLONNE 2 : mises à jour + calendrier ═════════
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.round(dash.width * 0.28)
            spacing: 14

            Carte {
                titre: ""
                Layout.fillWidth: true
                Layout.preferredHeight: 132
                color: Qt.rgba(dash.cWarn.r, dash.cWarn.g, dash.cWarn.b, 0.16)
                border.color: Qt.rgba(dash.cWarn.r, dash.cWarn.g, dash.cWarn.b, 0.35)

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: dash.upd.total !== undefined ? (dash.upd.total + " mises à jour") : "…"
                        font.pixelSize: 18; font.bold: true; color: dash.cText
                    }
                    Item { Layout.fillWidth: true }
                    IconButtonMini { glyph: "⟳"; onClicked: dash.api("/api/updates", null, function(d) { dash.upd = d || {}; }) }
                }
                Text {
                    text: "Pacman " + (dash.upd.pacman !== undefined ? dash.upd.pacman : "…")
                          + "  •  AUR " + (dash.upd.aur !== undefined ? dash.upd.aur : "…")
                          + (dash.upd.verifie ? "  ·  vérifié à " + dash.upd.verifie : "")
                    font.pixelSize: 11; color: dash.cTextDim
                }
                RowLayout {
                    spacing: 8
                    Rectangle {
                        height: 28; radius: 14; width: 150
                        color: Qt.rgba(dash.cWarn.r, dash.cWarn.g, dash.cWarn.b, 0.30)
                        Text {
                            anchors.centerIn: parent
                            text: "Mettre à jour"
                            font.pixelSize: 11; color: dash.cText
                        }
                        MouseArea { anchors.fill: parent; onClicked: dash.api("/api/updates", null, function(d) { dash.upd = d || {}; }) }
                    }
                    Text {
                        text: dash.upd.ok === false ? "pacman indisponible" : ""
                        font.pixelSize: 10; color: dash.cHot
                    }
                    Item { Layout.fillWidth: true }
                }
                Item { Layout.fillHeight: true }
            }

            Carte {
                titre: dash.mois[dash.calMonth] + " " + dash.calYear
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Aujourd'hui : " + dash.deux(dash.now.getDate()) + " "
                              + dash.mois[dash.now.getMonth()].substring(0, 4) + "."
                        font.pixelSize: 10; color: dash.cTextDim
                    }
                    Item { Layout.fillWidth: true }
                    IconButtonMini { glyph: "‹"; onClicked: dash.changeMois(-1) }
                    IconButtonMini { glyph: "›"; onClicked: dash.changeMois(1) }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 2

                    Repeater {
                        model: dash.jours
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.pixelSize: 9
                            color: dash.cTextDim
                        }
                    }
                    Repeater {
                        model: dash.premierJour(dash.calMonth, dash.calYear)
                               + dash.joursDansMois(dash.calMonth, dash.calYear)
                        delegate: Item {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            property int jour: index - dash.premierJour(dash.calMonth, dash.calYear) + 1
                            property bool actif: jour > 0
                                                   && jour === dash.now.getDate()
                                                   && dash.calMonth === dash.now.getMonth()
                                                   && dash.calYear === dash.now.getFullYear()
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: 6
                                color: actif ? Qt.rgba(dash.cAccent.r, dash.cAccent.g, dash.cAccent.b, 0.85)
                                             : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: parent.actif ? String(parent.jour) : ""
                                font.pixelSize: 11
                                color: parent.actif ? "#101018" : dash.cText
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // ═════════ COLONNE 3 : horloge/météo + tâches ═════════
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.round(dash.width * 0.32)
            spacing: 14

            Carte {
                titre: ""
                Layout.fillWidth: true
                Layout.preferredHeight: 186
                color: Qt.rgba(dash.cAccent.r, dash.cAccent.g, dash.cAccent.b, 0.30)
                border.color: Qt.rgba(dash.cAccent.r, dash.cAccent.g, dash.cAccent.b, 0.45)

                Text {
                    text: dash.heure()
                    font.pixelSize: 52
                    font.bold: true
                    color: dash.cText
                }
                Text {
                    text: (dash.wx.city || "Lyon") + "  ·  " + (dash.wx.label || "…")
                    font.pixelSize: 12
                    color: dash.cTextDim
                }
                Text {
                    text: dash.wx.temp !== undefined && dash.wx.temp !== null
                          ? dash.wx.temp + " °C" : "—"
                    font.pixelSize: 26
                    font.bold: true
                    color: dash.cText
                }
                Item { Layout.fillHeight: true }
            }

            Carte {
                titre: "TÂCHES"
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: (dash.tasks.done || 0) + "/" + (dash.tasks.total || 0)
                        font.pixelSize: 15; font.bold: true; color: dash.cText
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: Qt.rgba(dash.cAccent.r, dash.cAccent.g, dash.cAccent.b, 0.25)
                        Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 16; color: dash.cText }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (dash.newTask.length) {
                                    dash.api("/api/tasks", {action: "add", text: dash.newTask},
                                             function(d) { dash.tasks = d || {}; dash.newTask = ""; });
                                }
                            }
                        }
                    }
                }

                TextField {
                    Layout.fillWidth: true
                    placeholderText: "Nouvelle tâche…"
                    text: dash.newTask
                    font.pixelSize: 11
                    color: dash.cText
                    placeholderTextColor: dash.cTextDim
                    background: Rectangle {
                        radius: 8
                        color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.06)
                    }
                    onTextChanged: dash.newTask = text
                    onAccepted: {
                        dash.api("/api/tasks", {action: "add", text: dash.newTask},
                                 function(d) { dash.tasks = d || {}; dash.newTask = ""; });
                        text = "";
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: dash.tasks.items || []
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        spacing: 8
                        Rectangle {
                            width: 16; height: 16; radius: 4
                            color: modelData.done
                                   ? Qt.rgba(dash.cGood.r, dash.cGood.g, dash.cGood.b, 0.8)
                                   : Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.10)
                            Text { anchors.centerIn: parent; text: modelData.done ? "✓" : ""; font.pixelSize: 10; color: "#101018" }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dash.api("/api/tasks", {action: "toggle", id: modelData.id},
                                                    function(d) { dash.tasks = d || {}; })
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.text
                            font.pixelSize: 11
                            color: modelData.done ? dash.cTextDim : dash.cText
                            font.strikeout: !!modelData.done
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "✕"
                            font.pixelSize: 10
                            color: dash.cTextDim
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dash.api("/api/tasks", {action: "remove", id: modelData.id},
                                                    function(d) { dash.tasks = d || {}; })
                            }
                        }
                    }
                }
                Text {
                    visible: (dash.tasks.total || 0) === 0
                    text: "rien à faire"
                    font.pixelSize: 11
                    color: dash.cTextDim
                }
            }
        }
    }

    // Petit bouton rond réutilisé (⟳ ‹ › ⏮ ▶ ⏭)
    component IconButtonMini: Rectangle {
        id: mini
        property string glyph: ""
        property int size: 24
        signal clicked()
        width: mini.size; height: mini.size; radius: mini.size / 2
        color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.08)
        Text {
            anchors.centerIn: parent
            text: mini.glyph
            font.pixelSize: Math.round(mini.size * 0.55)
            color: dash.cText
        }
        MouseArea { anchors.fill: parent; onClicked: mini.clicked() }
    }
}
