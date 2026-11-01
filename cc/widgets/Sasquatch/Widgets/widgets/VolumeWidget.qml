// VolumeWidget.qml — widget `volume` (catalogue §6 / tranche v1d).
//
// Variantes :
//   compact  220x64   un seul slider (volume) + valeur + coupure du son
//   normal   360x180  volume + luminosité (2 lignes) + coupure du son
//
// Sources : Env.volume / Env.muted (/api/system/volume → {volume, muted}) et
// Env.brightness (/api/system/brightness → {brightness}). Écriture : POST
// {"v":0..100} et {"mute":bool} via Env.setVolume / Env.toggleMute /
// Env.setBrightness — le widget ne fait aucun XMLHttpRequest (brief §2).
// Le POST part au RELÂCHEMENT du slider (une écriture par geste, pas une par
// pixel), la valeur affichée reste locale jusqu'à confirmation du serveur.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "volume"

    readonly property bool showBrightness: !(root.options && root.options.showBrightness === false)
    readonly property real vol: Env.volume < 0 ? 0 : Env.volume
    readonly property real lum: Env.brightness < 0 ? 0 : Env.brightness
    readonly property bool known: Env.volume >= 0

    readonly property real innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real labelSize: Math.max(9, Math.min(13, Math.round(root.innerH * 0.10)))
    readonly property real valueSize: Math.max(10, Math.min(15, Math.round(root.innerH * 0.115)))
    readonly property real rowH: Math.max(26, Math.min(34, Math.round(root.innerH * 0.24)))
    readonly property real pillH: Math.max(26, Math.round(root.innerH * 0.19))
    readonly property real colSpacing: Math.max(4, Math.round(root.innerH * 0.05))
    // Glyphe à gauche du slider (correctif v1c-1).
    readonly property real glyphW: Math.max(12, Math.min(18, Math.round(root.rowH * 0.62)))
    // La pilule « son » ne s'affiche que si elle tient : sur une carte d'une
    // rangée (4x1 = 96 px) elle débordait sous la carte. Le mute reste
    // accessible par la valeur (clic) dans les deux variantes.
    readonly property int visibleRows: 1 + (root.showBrightness ? 1 : 0)
    readonly property bool showPill: (root.visibleRows * root.rowH + root.pillH
                                      + (root.visibleRows + 1) * root.colSpacing) <= root.innerH
    // Espace restant, pousse la pilule en bas SANS sortir de la carte.
    readonly property real gaps: (root.visibleRows + (root.showPill ? 1 : 0)) * root.colSpacing
    readonly property real spacerH: Math.max(0, root.innerH - root.visibleRows * root.rowH
                                                - (root.showPill ? root.pillH : 0) - root.gaps)
    readonly property real labelW: Math.round(Math.min(root.width * 0.34, 76))
    // Assez large pour « Son coupé » / « 51 % » : une valeur tronquée ne dit rien.
    readonly property real valueW: Math.round(Math.max(44, root.labelSize * 4.8))
    // États explicites (spec copy) : « — » = pas de mesure, sinon valeur.
    readonly property bool soundKnown: Env.volume >= 0
    readonly property bool lightKnown: Env.brightness >= 0
    readonly property string volText: !root.soundKnown ? "—"
                                     : (Env.muted ? "Son coupé" : Math.round(root.vol) + " %")
    readonly property string lumText: root.lightKnown ? (Math.round(root.lum) + " %") : "—"


    // ── Slider (piste 4 px, poignée 12 px, cible de clic = toute la ligne) ──
    component Sldr: Item {
        id: sl

        property real value: 0
        property color fillColor: Theme.vizA
        property bool active: true
        // Valeur locale tant que le serveur n'a pas confirmé (pas de saut).
        property real localV: -1
        property real dragV: 0
        property bool dragging: false

        signal commit(real v)

        readonly property real shown: sl.localV >= 0 ? sl.localV : sl.value
        readonly property real k: Math.max(0, Math.min(1, sl.shown / 100))

        implicitHeight: 30

        onValueChanged: {
            if (sl.localV >= 0 && Math.abs(sl.value - sl.localV) <= 1)
                sl.localV = -1;
        }

        function valueAt(px) {
            return Math.max(0, Math.min(100, Math.round(100 * px / Math.max(1, sl.width))));
        }

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: Theme.a(root.ink, 0.12)

            Rectangle {
                width: track.width * sl.k
                height: parent.height
                radius: 2
                color: sl.fillColor
                opacity: sl.active ? 1.0 : 0.45

                Behavior on width {
                    NumberAnimation {
                        duration: 90
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Rectangle {
            width: 12
            height: 12
            radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(sl.width - width, sl.width * sl.k - width / 2))
            color: sl.active ? Theme.ink : Theme.a(root.ink, 0.5)
            border.width: 1
            border.color: Theme.a(root.ink, 0.25)
        }

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            enabled: sl.active
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            onPressed: function (mouse) {
                sl.dragging = true;
                sl.dragV = sl.valueAt(mouse.x);
                sl.localV = sl.dragV;
            }
            onPositionChanged: function (mouse) {
                if (!sl.dragging)
                    return;
                sl.dragV = sl.valueAt(mouse.x);
                sl.localV = sl.dragV;
            }
            onReleased: {
                if (!sl.dragging)
                    return;
                sl.dragging = false;
                sl.commit(sl.dragV);
            }
            onCanceled: sl.dragging = false
        }
    }

    // ── Glyphes dessinés (correctif v1c-1) ────────────────────────────────
    // À gauche de chaque slider. Dessinés au Canvas comme BatIcon/WxIcon :
    // un émoji 🔊/☀ est rendu par la police couleur et casse la teinte.
    component SpkIcon: Canvas {
        id: spk

        property bool muted: false
        property color tint: Theme.ink

        function repaint() { requestPaint(); }

        onMutedChanged: repaint()
        onTintChanged: repaint()
        onWidthChanged: repaint()
        onHeightChanged: repaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var S = Math.min(width, height);
            if (S < 6)
                return;
            ctx.strokeStyle = spk.tint;
            ctx.fillStyle = spk.tint;
            ctx.lineWidth = Math.max(1.2, S * 0.085);
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            // Cône du haut-parleur.
            ctx.beginPath();
            ctx.moveTo(S * 0.08, S * 0.38);
            ctx.lineTo(S * 0.24, S * 0.38);
            ctx.lineTo(S * 0.44, S * 0.18);
            ctx.lineTo(S * 0.44, S * 0.82);
            ctx.lineTo(S * 0.24, S * 0.62);
            ctx.lineTo(S * 0.08, S * 0.62);
            ctx.closePath();
            ctx.fill();

            if (!spk.muted) {
                ctx.beginPath();
                ctx.arc(S * 0.48, S * 0.50, S * 0.18, -0.85, 0.85);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(S * 0.48, S * 0.50, S * 0.32, -0.75, 0.75);
                ctx.stroke();
            } else {
                // Barre de coupure.
                ctx.beginPath();
                ctx.moveTo(S * 0.12, S * 0.88);
                ctx.lineTo(S * 0.88, S * 0.12);
                ctx.stroke();
            }
        }
    }

    component SunIcon: Canvas {
        id: sun

        property color tint: Theme.ink

        function repaint() { requestPaint(); }

        onTintChanged: repaint()
        onWidthChanged: repaint()
        onHeightChanged: repaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var S = Math.min(width, height);
            if (S < 6)
                return;
            ctx.strokeStyle = sun.tint;
            ctx.lineWidth = Math.max(1.2, S * 0.085);
            ctx.lineCap = "round";
            var c = S / 2;
            ctx.beginPath();
            ctx.arc(c, c, S * 0.21, 0, Math.PI * 2);
            ctx.stroke();
            for (var i = 0; i < 8; ++i) {
                var a = i * Math.PI / 4;
                ctx.beginPath();
                ctx.moveTo(c + Math.cos(a) * S * 0.32, c + Math.sin(a) * S * 0.32);
                ctx.lineTo(c + Math.cos(a) * S * 0.46, c + Math.sin(a) * S * 0.46);
                ctx.stroke();
            }
        }
    }

    // ── compact : un seul slider (volume) ─────────────────────────────────
    Row {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 8

        SpkIcon {
            width: root.glyphW
            height: root.glyphW
            anchors.verticalCenter: parent.verticalCenter
            muted: Env.muted
            tint: Env.muted ? Theme.hot : root.ink
        }

        Sldr {
            width: Math.max(20, parent.width - root.glyphW - root.valueW - muteBtn.width - 3 * parent.spacing)
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
            value: root.vol
            active: root.interactive && root.known
            fillColor: Env.muted ? Theme.a(root.ink, 0.4) : Theme.vizA
            onCommit: function (v) {
                Env.setVolume(v);
            }
        }

        Text {
            id: muteBtn
            anchors.verticalCenter: parent.verticalCenter
            width: root.valueW
            text: !root.soundKnown ? "—" : (Env.muted ? "⊘" : Math.round(root.vol) + " %")
            color: (Env.muted || !root.soundKnown) ? root.inkDim : root.ink
            font.pixelSize: root.valueSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: root.interactive
                onClicked: Env.toggleMute()
            }
        }
    }

    // ── normal : volume + luminosité + coupure du son ─────────────────────
    Column {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.colSpacing

        // Volume
        Item {
            width: parent.width
            height: root.rowH

            Text {
                id: volLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelW
                text: "Son"
                color: root.soundKnown ? root.ink : root.inkDim
                font.pixelSize: root.labelSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
            }

            // Glyphe haut-parleur, à gauche du slider (correctif v1c-1).
            SpkIcon {
                id: volGlyph
                anchors.left: volLabel.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: root.glyphW
                height: root.glyphW
                muted: Env.muted
                tint: Env.muted ? Theme.hot : root.ink
            }

            Sldr {
                anchors.left: volGlyph.right
                anchors.right: volValue.left
                anchors.leftMargin: 6
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                value: root.vol
                active: root.interactive && root.known
                fillColor: Env.muted ? Theme.a(root.ink, 0.4) : Theme.vizA
                onCommit: function (v) {
                    Env.setVolume(v);
                }
            }

            Text {
                id: volValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.valueW
                text: root.volText
                color: (Env.muted || !root.soundKnown) ? root.inkDim : root.ink
                font.pixelSize: root.valueSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.interactive
                    onClicked: Env.toggleMute()
                }
            }
        }

        // Luminosité
        Item {
            width: parent.width
            height: root.rowH
            visible: root.showBrightness

            Text {
                id: lumLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.labelW
                text: "Luminosité"
                color: root.lightKnown ? root.ink : root.inkDim
                font.pixelSize: root.labelSize
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                verticalAlignment: Text.AlignVCenter
            }

            // Glyphe soleil, à gauche du slider (correctif v1c-1).
            SunIcon {
                id: lumGlyph
                anchors.left: lumLabel.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: root.glyphW
                height: root.glyphW
                tint: Theme.warn
            }

            Sldr {
                anchors.left: lumGlyph.right
                anchors.right: lumValue.left
                anchors.leftMargin: 6
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                value: root.lum
                active: root.interactive && Env.brightness >= 0
                fillColor: Theme.mix(Theme.vizA, Theme.ink, 0.45)
                onCommit: function (v) {
                    Env.setBrightness(v);
                }
            }

            Text {
                id: lumValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.valueW
                text: root.lumText
                color: root.lightKnown ? root.ink : root.inkDim
                font.pixelSize: root.valueSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        // Ressort : pousse la pilule en bas de la carte (jamais dehors).
        Item {
            width: 1
            height: root.spacerH
        }

        // Pilule « son » : bascule mute, cible ≥ 30 px. Masquée quand la
        // carte est trop courte (4x1) : le mute reste sur la valeur (clic).
        Rectangle {
            visible: root.showPill
            width: Math.min(parent.width, mutePill.implicitWidth + 24)
            height: root.pillH
            radius: Theme.radiusBtn
            color: Theme.a(Theme.glassBtn, Theme.alphaBtn)
            border.width: 1
            border.color: pillHover2.containsMouse ? Theme.halo : Theme.border

            Text {
                id: mutePill
                anchors.centerIn: parent
                text: !root.soundKnown ? "Réglage du son indisponible"
                      : (Env.muted ? "⊘ Son coupé" : "● Son actif")
                color: !root.soundKnown ? Theme.warn : root.inkDim
                font.pixelSize: Math.max(9, Math.round(parent.height * 0.48))
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            MouseArea {
                id: pillHover2
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: root.interactive && root.soundKnown
                onClicked: Env.toggleMute()
            }
        }
    }
}
