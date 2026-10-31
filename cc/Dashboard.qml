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
        property string titre: ""
        radius: 16
        color: Qt.rgba(dash.cCard.r, dash.cCard.g, dash.cCard.b, 0.55)
        border.width: 1
        border.color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.06)
        default property alias contenu: inner.data
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
        }
        Text {
            text: parent.titre
            visible: text.length > 0
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            font.pixelSize: 10
            font.letterSpacing: 1.2
            font.capitalization: Font.AllUppercase
            color: dash.cTextDim
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

    // Petit bouton rond réutilisé (⟳ ‹ ›)
    component IconButtonMini: Rectangle {
        id: mini
        property string glyph: ""
        signal clicked()
        width: 24; height: 24; radius: 12
        color: Qt.rgba(dash.cText.r, dash.cText.g, dash.cText.b, 0.08)
        Text { anchors.centerIn: parent; text: mini.glyph; font.pixelSize: 13; color: dash.cText }
        MouseArea { anchors.fill: parent; onClicked: mini.clicked() }
    }
}
