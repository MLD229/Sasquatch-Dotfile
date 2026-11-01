// BtProbe.qml — sonde Bluetooth (Quickshell.Bluetooth), chargée SEULEMENT par
// Connectivity.qml quand le module existe sur le disque (voir NetProbe.qml
// pour la raison : un import manquant tue le fichier, pas le shell).
//
// BlueZ répond en asynchrone : `defaultAdapter` est null au démarrage puis
// arrive (~1-2 s). Les propriétés ci-dessous sont des LIAISONS, donc elles se
// remplissent seules ; aucune lecture ponctuelle au chargement.
import QtQuick
import Sasquatch.Widgets 1.0
import Quickshell.Bluetooth

QtObject {
    id: probe

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: probe.adapter !== null
    readonly property string adapterName: probe.present ? ("" + probe.adapter.name) : ""
    readonly property bool enabled: probe.present ? (probe.adapter.enabled === true) : false
    // BluetoothAdapterState : Disabled, Enabled, Enabling, Disabling, Blocked.
    readonly property int adapterState: probe.present ? probe.adapter.state : -1

    readonly property var devices: {
        if (!probe.present)
            return [];
        var out = [];
        var vals = probe.adapter.devices.values;
        for (var i = 0; i < vals.length; ++i) {
            var d = vals[i];
            out.push({ name: (typeof d.name === "string" && d.name.length > 0) ? d.name
                             : ("" + (d.address || "")),
                       connected: d.connected === true,
                       paired: d.paired === true,
                       state: d.state });
        }
        return out;
    }

    readonly property int connectedCount: {
        var n = 0;
        for (var i = 0; i < probe.devices.length; ++i) {
            if (probe.devices[i].connected)
                n += 1;
        }
        return n;
    }

    readonly property var firstConnected: {
        for (var i = 0; i < probe.devices.length; ++i) {
            if (probe.devices[i].connected)
                return probe.devices[i];
        }
        return null;
    }

    function stateLabel() {
        switch (probe.adapterState) {
        case BluetoothAdapterState.Enabled:
            return "activé";
        case BluetoothAdapterState.Disabled:
            return "désactivé";
        case BluetoothAdapterState.Enabling:
            return "activation…";
        case BluetoothAdapterState.Disabling:
            return "désactivation…";
        case BluetoothAdapterState.Blocked:
            return "bloqué (rfkill)";
        }
        return "indisponible";
    }

    Component.onCompleted: {
        if (typeof Connectivity !== "undefined")
            Connectivity.btProbe = probe;
    }
}
