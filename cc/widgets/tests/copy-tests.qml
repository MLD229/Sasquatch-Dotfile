// copy-tests.qml — vérifie les helpers de microcopie (spec copy-widgets §3).
//
// Ces règles portent sur des chaînes que le rendu ne montre pas toujours
// (une capture peut être la 4e notification d'une liste de 3) : on les teste
// donc directement, sur des charges utiles RÉELLES relevées sur
// /api/notifications, plus un cas synthétique de nom de fichier.
//
// Sortie : une ligne `COPY-OK <cas>` ou `COPY-FAIL <cas> → <obtenu>`.
import QtQuick
import Quickshell
import Sasquatch.Widgets 1.0

ShellRoot {
    id: root

    // Charge utile réelle (GET /api/notifications, 2026-11-01) : app
    // `notify-send`, icône et corps = nom de fichier de la capture.
    readonly property var realShot: ({
        app: "notify-send",
        icon: "/home/momo/Pictures/Screenshots/20261031_202801_736916312.png",
        summary: "Screenshot",
        body: "20261031_202801_736916312.png — copié ✓"
    })

    readonly property var realPlain: ({
        app: "Notifications du système",
        icon: "drive-removable-media-usb",
        summary: "Un périphérique USB a été détecté.",
        body: "Wacom Co.,Ltd. Intuos BT S a été branché."
    })

    readonly property var techName: ({
        app: "notify-send",
        icon: "",
        summary: "notify-send-2026-10-31",
        body: "test"
    })

    property int fails: 0

    function check(name, got, want) {
        if (got === want) {
            console.log("COPY-OK " + name);
            return;
        }
        fails += 1;
        console.log("COPY-FAIL " + name + " → «" + got + "» (attendu «" + want + "»)");
    }

    Timer {
        interval: 600
        repeat: false
        running: true
        onTriggered: {
            root.check("titre d'une capture horodatée", Notifs.humanTitle(root.realShot),
                       "Capture d'écran 20:28");
            root.check("corps débarrassé du nom de fichier", Notifs.humanBody(root.realShot),
                       "copié ✓");
            root.check("titre d'une notification normale", Notifs.humanTitle(root.realPlain),
                       "Un périphérique USB a été détecté.");
            root.check("corps d'une notification normale", Notifs.humanBody(root.realPlain),
                       "Wacom Co.,Ltd. Intuos BT S a été branché.");
            root.check("titre d'une chaîne technique sans heure", Notifs.humanTitle(root.techName),
                       "Notification");
            console.log("COPY-DONE " + root.fails);
        }
    }
}
