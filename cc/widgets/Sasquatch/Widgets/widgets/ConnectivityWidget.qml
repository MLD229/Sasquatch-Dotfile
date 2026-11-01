// ConnectivityWidget.qml — widget `connectivity` : réseau, Bluetooth, audio.
//
// Variantes :
//   compact  220x64   deux lignes courtes (réseau, puis Bluetooth + audio)
//   normal   360x180  titre + trois lignes « Catégorie · état » + commande
//
// Source : Connectivity (singleton). Il parle à Quickshell.Networking
// (wifi/ethernet, via NetProbe.qml chargé seulement si le module existe),
// Quickshell.Bluetooth (via BtProbe.qml) et parse `wpctl status` (audio).
// Ici, aucune sonde, aucun XMLHttpRequest, aucune couleur en dur.
//
// Copy (spec §3) : UNE information par ligne — `Wi-Fi · wlan0`,
// `Bluetooth · Activé` — jamais « BT actif · adaptateur actif ». Un outil
// manquant est nommé avec sa commande d'installation, jamais un jargon.
import QtQuick
import Sasquatch.Widgets 1.0

WidgetBase {
    id: root
    widgetType: "connectivity"

    readonly property int innerH: Math.max(8, root.height - 2 * root.pad)
    readonly property real mainSize: Math.max(9, Math.min(root.compact ? 12 : 14,
                                                         Math.round(root.innerH * (root.compact ? 0.23 : 0.10))))
    readonly property real subSize: Math.max(8, Math.round(root.mainSize * 0.82))
    readonly property real headH: root.compact ? 0 : Math.round(root.innerH * 0.15)

    // ── État réseau, en une phrase compréhensible ─────────────────────────
    readonly property var netIface: Connectivity.firstIface()
    readonly property string netValue: {
        if (!Connectivity.checked)
            return "vérification…";
        if (Connectivity.netReady && Connectivity.netActive !== null) {
            var a = Connectivity.netActive;
            if (a.kind === "wifi")
                return "Wi-Fi · " + (a.ssid.length > 0 ? a.ssid : a.name);
            return "Ethernet · " + a.name;
        }
        if (Connectivity.netReady)
            return "Wi-Fi · aucune connexion";
        // Module présent, backend absent : c'est le cas de cette machine (iwd).
        if (Connectivity.hasNetworking)
            return "Wi-Fi · NetworkManager non installé";
        return "Gestion du réseau indisponible";
    }
    readonly property string netHint: (Connectivity.checked && !Connectivity.netReady)
                                      ? (Connectivity.hasNetworking ? "sudo pacman -S networkmanager"
                                                                    : "sudo pacman -S quickshell")
                                      : ""
    readonly property color netColor: (!Connectivity.checked) ? root.inkDim
                                    : (Connectivity.netReady ? (Connectivity.netActive !== null
                                                               ? Theme.good : Theme.warn)
                                                             : Theme.warn)

    readonly property string btValue: {
        if (!Connectivity.checked)
            return "Bluetooth · vérification…";
        if (!Connectivity.hasBluetooth)
            return "Bluetooth · indisponible";
        if (!Connectivity.btPresent)
            return "Bluetooth · aucun adaptateur";
        if (Connectivity.btConnected > 0)
            return "Bluetooth · " + Connectivity.btProbe.firstConnected.name;
        return "Bluetooth · " + (Connectivity.btOn ? "Activé" : "Désactivé");
    }
    readonly property string btHint: (Connectivity.checked && !Connectivity.hasBluetooth)
                                     ? "sudo pacman -S quickshell" : ""
    readonly property color btColor: (!Connectivity.checked) ? root.inkDim
                                   : (Connectivity.btOn ? Theme.good : root.inkDim)

    readonly property string audioValue: {
        if (!Connectivity.hasWpctl)
            return "Son · réglage indisponible";
        if (!Connectivity.audioOk || Connectivity.audioMain.length === 0)
            return "Son · périphérique inconnu";
        return "Son · " + Connectivity.audioMain;
    }
    readonly property string audioHint: (!Connectivity.hasWpctl && Connectivity.checked)
                                        ? "sudo pacman -S wireplumber" : ""
    readonly property color audioColor: (Connectivity.hasWpctl && Connectivity.audioOk)
                                        ? root.ink : root.inkDim

    // Une ligne : « Catégorie · état » + commande d'installation si besoin.
    component Line: Item {
        id: line

        property string value: ""
        property string hint: ""
        property color valueColor: root.ink

        width: parent ? parent.width : 0
        height: line.hint.length > 0 ? Math.round(root.subSize * 2.5) : Math.round(root.mainSize * 1.5)

        Text {
            id: label
            anchors.left: parent.left
            anchors.top: parent.top
            width: parent.width
            text: line.value
            color: line.valueColor
            font.pixelSize: root.mainSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: label.bottom
            visible: line.hint.length > 0
            text: line.hint
            color: root.inkDim
            font.pixelSize: root.subSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── compact : deux lignes ─────────────────────────────────────────────
    Column {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(2, Math.round(root.innerH * 0.05))
        clip: true

        Text {
            width: parent.width
            text: root.netValue
            color: root.netColor
            font.pixelSize: root.mainSize
            font.weight: Font.Medium
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            width: parent.width
            text: root.btValue + (Connectivity.hasWpctl ? "  ·  " + Connectivity.audioMain : "")
            color: root.inkDim
            font.pixelSize: root.subSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    // ── normal : titre + trois lignes ─────────────────────────────────────
    Column {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(4, Math.round(root.innerH * 0.035))
        clip: true

        Item {
            width: parent.width
            height: root.headH

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Connexions"
                color: root.ink
                font.pixelSize: root.mainSize
                font.weight: Font.Medium
            }
        }

        Line {
            value: root.netValue
            hint: root.netHint
            valueColor: root.netColor
        }
        Line {
            value: root.btValue
            hint: root.btHint
            valueColor: root.btColor
        }
        Line {
            value: root.audioValue
            hint: root.audioHint
            valueColor: root.audioColor
        }
    }
}
