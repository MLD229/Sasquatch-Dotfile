// NetProbe.qml — sonde réseau (Quickshell.Networking), chargée SEULEMENT par
// Connectivity.qml quand le module existe sur le disque.
//
// Fichier séparé volontairement : un `import Quickshell.Networking` qui échoue
// fait échouer TOUT le fichier. Isolé ici, l'échec reste un Loader/Component
// en erreur — le shell et le widget survivent (brief : jamais de crash).
// Aucun rendu : QtObject, la sonde ne sert qu'à exposer l'état.
import QtQuick
import Sasquatch.Widgets 1.0
import Quickshell.Networking

QtObject {
    id: probe

    // NetworkBackendType : None = 0, NetworkManager = 1.
    readonly property int backend: Networking.backend
    readonly property bool wifiEnabled: Networking.wifiEnabled
    // NetworkConnectivity : Unknown, None, Portal, Limited, Full.
    readonly property int connectivity: Networking.connectivity

    // Un enregistrement par interface : { name, kind, connected, state, ssid }.
    readonly property var devices: {
        var out = [];
        var vals = Networking.devices.values;
        for (var i = 0; i < vals.length; ++i) {
            var d = vals[i];
            var kind = (d.type === DeviceType.Wifi) ? "wifi"
                     : (d.type === DeviceType.Wired) ? "wired" : "autre";
            var ssid = "";
            // WifiNetwork: seul le réseau courant nous intéresse ; les noms de
            // propriétés varient (ssid / name), on lit ce qui existe.
            if (kind === "wifi" && d.networks) {
                var nets = d.networks.values;
                for (var j = 0; j < nets.length; ++j) {
                    var n = nets[j];
                    var label = (typeof n.ssid === "string" && n.ssid.length > 0) ? n.ssid
                              : (typeof n.name === "string" ? n.name : "");
                    if (n.connected === true && label.length > 0) {
                        ssid = label;
                        break;
                    }
                }
            }
            out.push({ name: "" + d.name, kind: kind, connected: d.connected === true,
                       state: d.state, ssid: ssid });
        }
        return out;
    }

    readonly property string backendLabel: (probe.backend === NetworkBackendType.NetworkManager)
                                           ? "NetworkManager" : "aucun"
    readonly property bool ready: probe.backend === NetworkBackendType.NetworkManager

    // Interface active : wifi connectée d'abord, puis filaire.
    readonly property var active: {
        var best = null;
        for (var i = 0; i < probe.devices.length; ++i) {
            var d = probe.devices[i];
            if (!d.connected)
                continue;
            if (best === null || d.kind === "wifi")
                best = d;
        }
        return best;
    }

    function connectivityLabel() {
        switch (probe.connectivity) {
        case NetworkConnectivity.None:
            return "hors ligne";
        case NetworkConnectivity.Portal:
            return "portail captif";
        case NetworkConnectivity.Limited:
            return "connexion limitée";
        case NetworkConnectivity.Full:
            return "connecté";
        }
        return "inconnu";
    }

    Component.onCompleted: {
        if (typeof Connectivity !== "undefined")
            Connectivity.netProbe = probe;
    }
}
