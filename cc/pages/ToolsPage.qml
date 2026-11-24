// ToolsPage.qml — page « Outils » du CC.
//
// Habillage v2 (spec microcopie) : mêmes routes et mêmes délais que l'ancienne
// page (capture, reconnaissance musicale, recherche d'image/OCR, traduction),
// mais quatre blocs lisibles — titre, une ligne d'explication, UNE action
// principale, puis l'état du résultat sous le bloc. Un outil dont la
// dépendance manque est grisé avec la raison ET la commande d'install ; les
// autres blocs continuent de fonctionner.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../qml"
import Sasquatch.Widgets 1.0

Item {
    id: toolsPage

    property string shotStatus: ""
    property string imgStatus: ""
    property var toolHealth: ({})

    signal screenshotRequested(string mode)
    signal hidePanel()
    signal showPanel()

    // Échap ne doit pas fermer le CC pendant la saisie (contrat avec le shell).
    readonly property bool searchFocused: imgQuery.activeFocus

    function toolOk(k) {
        var h = toolsPage.toolHealth ? toolsPage.toolHealth[k] : null;
        return !h || h.ok !== false;
    }

    // Message humain + commande d'install (jamais un nom de paquet nu).
    function toolWhy(k) {
        var h = toolsPage.toolHealth ? toolsPage.toolHealth[k] : null;
        if (!h || h.ok !== false)
            return "";
        var msg = h.resume
                  ? ((h.casse && h.casse.length > 0 ? "Outil cassé : " : "Non installé : ") + h.resume)
                  : "Indisponible";
        if (h.hint)
            msg += "  ·  " + h.hint;
        return msg;
    }

    function searchImage() {
        if (!toolsPage.toolOk("imgsearch"))
            return;
        toolsPage.imgStatus = "Recherche en cours…";
        Api.post("/api/imgsearch", { q: imgQuery.text }, function (res) {
            toolsPage.imgStatus = (res && res.ok) ? "Recherche lancée."
                                                  : ("Impossible de lancer la recherche. " + ((res && res.error) || "Réessaie."));
        }, 130000);
    }

    property bool recognizeBusy: false
    property string recognizeResult: ""

    function recognize() {
        if (!toolsPage.toolOk("finder") || toolsPage.recognizeBusy)
            return;
        toolsPage.recognizeBusy = true;
        toolsPage.recognizeResult = "";
        Api.post("/api/music/finder", null, function (res) {
            toolsPage.recognizeBusy = false;
            if (res && res.recognized)
                toolsPage.recognizeResult = res.title + (res.artist ? " — " + res.artist : "");
            else if (res && res.error)
                toolsPage.recognizeResult = res.error;      // vrai motif (songrec absent, réseau…)
            else if (res)
                toolsPage.recognizeResult = "Non reconnu. Réessaie dans un endroit plus calme.";
            else
                toolsPage.recognizeResult = "Serveur injoignable — réessaie dans un instant.";
        }, 120000);
    }

    property bool translateBusy: false
    property string detectedText: ""
    property string translatedText: ""

    function translateScreen() {
        if (!toolsPage.toolOk("translate") || toolsPage.translateBusy)
            return;
        toolsPage.translateBusy = true;
        toolsPage.detectedText = "";
        toolsPage.translatedText = "";
        toolsPage.hidePanel();
        Api.post("/api/translate", null, function (res) {
            toolsPage.translateBusy = false;
            toolsPage.showPanel();
            if (res && res.ok && res.translation) {
                toolsPage.detectedText = res.text || "";
                toolsPage.translatedText = res.translation;
            } else {
                toolsPage.translatedText = "La traduction a échoué. " + ((res && res.error) || "Réessaie.");
            }
        }, 120000);
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Api.get("/api/tools/health", function (res) {
            if (res)
                toolsPage.toolHealth = res;
        })
    }

    // Bouton unique du style verre (même échelle de rayon que les widgets).
    component ActionButton: Rectangle {
        id: btn
        property string label: ""
        property bool busy: false
        property bool enabledByTool: true
        signal activated()

        implicitHeight: 30
        implicitWidth: Math.max(96, btnText.implicitWidth + 24)
        radius: Theme.radiusBtn
        opacity: btn.enabledByTool ? 1 : 0.4
        color: btnArea.containsMouse && btn.enabledByTool
               ? Theme.a(Theme.text, 0.12) : Theme.a(Theme.text, 0.06)
        // Aucun contour au repos (brief transparence) : le trait n'apparaît
        // qu'au survol.
        border.width: btnArea.containsMouse && btn.enabledByTool ? 1 : 0
        border.color: Theme.a(Theme.text, 0.10)
        Behavior on color { ColorAnimation { duration: 90 } }

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.busy ? "En cours…" : btn.label
            color: Theme.ink
            font.pixelSize: 11
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledByTool && !btn.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    // Empilement SERRÉ (brief bugs §4) : une Column, pas une ColumnLayout qui
    // répartit la hauteur restante. Les cartes gardent leur hauteur naturelle,
    // la dernière reste alignée en haut, et l'écart est exactement
    // Theme.spacing — rien ne s'étire.
    Column {
        id: cards
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacing

        // ── 01 · Capture d'écran ──────────────────────────────────────────
        GlassCard {
            width: cards.width
            title: "Capture d'écran"
            subtitle: "Enregistrer une image de l'écran, d'une fenêtre ou d'une zone."

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Zone"
                    enabledByTool: toolsPage.toolOk("capture")
                    onActivated: toolsPage.screenshotRequested("area")
                }
                ActionButton {
                    label: "Fenêtre"
                    enabledByTool: toolsPage.toolOk("capture")
                    onActivated: toolsPage.screenshotRequested("window")
                }
                ActionButton {
                    label: "Écran entier"
                    enabledByTool: toolsPage.toolOk("capture")
                    onActivated: toolsPage.screenshotRequested("full")
                }
                Item { Layout.fillWidth: true }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: toolsPage.toolOk("capture") ? toolsPage.shotStatus
                                                  : toolsPage.toolWhy("capture")
                color: toolsPage.toolOk("capture") ? Theme.inkDim : Theme.hot
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        // ── 02 · Reconnaître une musique ──────────────────────────────────
        GlassCard {
            width: cards.width
            title: "Reconnaître une musique"
            subtitle: "Écouter quelques secondes et donner le titre du morceau."

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Écouter"
                    busy: toolsPage.recognizeBusy
                    enabledByTool: toolsPage.toolOk("finder")
                    onActivated: toolsPage.recognize()
                }
                Text {
                    Layout.fillWidth: true
                    text: toolsPage.toolOk("finder")
                          ? (toolsPage.recognizeBusy ? "Écoute en cours…" : toolsPage.recognizeResult)
                          : toolsPage.toolWhy("finder")
                    color: toolsPage.toolOk("finder") ? Theme.inkDim : Theme.hot
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        // ── 03 · Chercher une image ───────────────────────────────────────
        GlassCard {
            width: cards.width
            title: "Chercher une image"
            subtitle: "Avec un mot-clé, ou en analysant une zone de l'écran (texte détecté puis images proches)."

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: imgQuery
                    Layout.fillWidth: true
                    placeholderText: "mot-clé — laisse vide pour analyser une zone de l'écran"
                    color: Theme.ink
                    font.pixelSize: 11
                    placeholderTextColor: Theme.inkDim
                    background: Rectangle {
                        radius: Theme.radiusBtn
                        color: Theme.a(Theme.text, 0.06)
                        border.width: imgQuery.activeFocus ? 1 : 0
                        border.color: Theme.a(Theme.accent, 0.55)
                    }
                    Keys.onReturnPressed: toolsPage.searchImage()
                }

                ActionButton {
                    label: "Chercher"
                    enabledByTool: toolsPage.toolOk("imgsearch")
                    onActivated: toolsPage.searchImage()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: toolsPage.toolOk("imgsearch") ? toolsPage.imgStatus
                                                    : toolsPage.toolWhy("imgsearch")
                color: toolsPage.toolOk("imgsearch") ? Theme.inkDim : Theme.hot
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        // ── 04 · Traduire ─────────────────────────────────────────────────
        GlassCard {
            width: cards.width
            title: "Traduire"
            subtitle: "Sélectionner une zone de l'écran pour en obtenir la traduction."

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    label: "Sélectionner une zone"
                    busy: toolsPage.translateBusy
                    enabledByTool: toolsPage.toolOk("translate")
                    onActivated: toolsPage.translateScreen()
                }
                Text {
                    Layout.fillWidth: true
                    visible: !toolsPage.toolOk("translate")
                    text: toolsPage.toolWhy("translate")
                    color: Theme.hot
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                // Toujours une ligne de haut : la place du texte détecté est
                // réservée, l'apparition ne décale rien (brief bugs §4).
                Layout.preferredHeight: 14
                text: toolsPage.detectedText.length > 0
                      ? "Texte détecté · " + toolsPage.detectedText : ""
                color: Theme.inkDim
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // Zone de résultat : la PLACE est réservée dès le départ (130 px),
            // donc le bloc ne change pas de hauteur quand la traduction arrive.
            // Tant qu'il n'y a rien, une ligne d'attente discrète occupe la
            // zone au lieu d'un trou (brief bugs §4).
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                Layout.minimumHeight: 130

                ScrollView {
                    anchors.fill: parent
                    visible: toolsPage.translatedText.length > 0
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    TextArea {
                        text: toolsPage.translatedText
                        readOnly: true
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        font.pixelSize: 14
                        color: Theme.ink
                        selectByMouse: true
                        background: Rectangle {
                            color: Theme.a(Theme.text, 0.04)
                            radius: Theme.radiusBtn
                        }
                        padding: 8
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: Math.max(1, parent.width - 16)
                    visible: toolsPage.translatedText.length === 0
                    text: toolsPage.translateBusy ? "Sélection en cours…"
                                                  : "Le résultat s'affichera ici."
                    color: Theme.inkDim
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}