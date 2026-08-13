// Sasquatch Control Center — Api.qml
// Helper HTTP vers le serveur local (métriques, MPD, finder…).
import QtQml

QtObject {
    readonly property string base: "http://127.0.0.1:8765"

    function get(path, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", base + path);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try { cb(JSON.parse(xhr.responseText)); }
                catch (e) { cb(null); }
            }
        };
        xhr.send();
    }

    function post(path, body, cb) {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", base + path);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (cb) {
                    try { cb(JSON.parse(xhr.responseText)); }
                    catch (e) { cb(null); }
                }
            }
        };
        xhr.send(JSON.stringify(body || {}));
    }
}
