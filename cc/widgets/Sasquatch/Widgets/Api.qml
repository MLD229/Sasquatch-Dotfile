// Api.qml — singleton : SEUL point d'entrée HTTP du système de widgets (CC 8765).
//
// Règle (brief §2) : un widget ne fait AUCUN XMLHttpRequest lui-même. Il lit
// Theme / Env / Music, qui passent par ce singleton.
// Règle : une panne du serveur ne casse jamais le shell — `online` passe à
// faux, l'appelant reçoit `null` et garde ses valeurs précédentes.
pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: api

    // Surcharge de TEST (harnais, machine où 8765 est occupé par un autre
    // utilisateur) : SASQUATCH_CC_URL=http://127.0.0.1:8799. Sans variable,
    // c'est l'adresse du service — comportement inchangé.
    readonly property string base: {
        var v = Quickshell.env("SASQUATCH_CC_URL");
        return (typeof v === "string" && v.length > 0) ? v : "http://127.0.0.1:8765";
    }

    // État observable (le harnais affiche `online` : preuve que le serveur vit).
    property bool online: false
    property string lastError: ""
    property int okCount: 0
    property int failCount: 0
    property int lastStatus: 0

    // ── Transport ─────────────────────────────────────────────────────────
    // `retries` : un GET est retenté une fois (démarrage du serveur), un POST
    // jamais (on ne veut pas rejouer une écriture).
    // `timeoutMs` : optionnel (défaut 3000). Les routes OCR/IA (imgsearch,
    // translate, finder) répondent en dizaines de secondes : sans ce paramètre
    // le POST était coupé avant la réponse (v1c-1).
    function _call(method, path, body, cb, retries, timeoutMs) {
        var left = (retries === undefined) ? 0 : retries;
        var xhr = new XMLHttpRequest();
        xhr.timeout = (typeof timeoutMs === "number" && timeoutMs > 0) ? timeoutMs : 3000;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                data = null;
            }
            api.lastStatus = xhr.status;
            if (xhr.status >= 200 && xhr.status < 300 && data !== null) {
                api.online = true;
                api.okCount += 1;
                api.lastError = "";
                if (cb)
                    cb(data);
                return;
            }
            if (left > 0) {
                api._call(method, path, body, cb, left - 1);
                return;
            }
            api.failCount += 1;
            if (xhr.status === 0)
                api.online = false;
            api.lastError = method + " " + path + " → " + xhr.status;
            if (cb)
                cb(null);
        };
        xhr.open(method, api.base + path);
        if (method === "POST") {
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.send(JSON.stringify(body || {}));
        } else {
            xhr.send(null);
        }
    }

    function get(path, cb, timeoutMs) {
        api._call("GET", path, null, cb, 1, timeoutMs);
    }

    function post(path, body, cb, timeoutMs) {
        api._call("POST", path, body || {}, cb, 0, timeoutMs);
    }
}
