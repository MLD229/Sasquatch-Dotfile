// Ui.qml — singleton : contrôleur de popups (un seul ouvert à la fois).
//
// Brief §4 : un popupController central. Les modules n'ouvrent jamais une
// fenêtre eux-mêmes : ils appellent Ui.open("calendar") etc., et shell.qml
// affiche LA popup correspondante (une surface par popup, jamais une surface
// qui grandit).
pragma Singleton
import QtQuick

QtObject {
    id: ui

    property string popup: ""          // "", "calendar", "volume", "network", "notifications", "windows", "addapp", "appmenu"
    property string windowClass: ""    // contexte de la popup "windows"
    property string windowTitle: ""    // contexte de la popup "windows"
    // Contexte de la popup "appmenu" (clic droit sur une app de la barre).
    property string appMenuKind: ""    // "pinned" | "running"
    property string appMenuId: ""      // id bar.json (épinglée) ou id .desktop résolu
    property string appMenuClass: ""   // classe Hyprland
    property string appMenuDesktop: "" // id .desktop (sans .desktop)
    property string appMenuTitle: ""   // libellé lisible

    // ── Registre des cibles cliquables (mesures réelles, brief v2 §2/§5) ──
    // Chaque composant cliquable s'enregistre à sa création et se retire à sa
    // destruction. `dumpRects()` relit la géométrie VIVANTE au moment de
    // l'appel IPC : c'est la preuve « bouton ≥ 38 px, centre identique »,
    // sans simulateur de souris (absent de ce poste).
    property var tracked: []

    function track(name, item, hitArea) {
        ui.tracked.push({ name: name, item: item, hit: hitArea || null });
    }

    function untrack(item) {
        var out = [];
        for (var i = 0; i < ui.tracked.length; i++) {
            if (ui.tracked[i].item !== item)
                out.push(ui.tracked[i]);
        }
        ui.tracked = out;
    }

    function relRect(it) {
        var p = it.mapToItem(null, 0, 0);
        return {
            x: Math.round(p.x), y: Math.round(p.y),
            w: Math.round(it.width), h: Math.round(it.height)
        };
    }

    function dumpRects() {
        var out = [];
        for (var i = 0; i < ui.tracked.length; i++) {
            var e = ui.tracked[i];
            if (!e.item)
                continue;
            var r = null;
            try {
                r = ui.relRect(e.item);
            } catch (err) {
                continue;
            }
            if (!r || r.w <= 0 || r.h <= 0)
                continue;
            var o = {
                name: e.name, x: r.x, y: r.y, w: r.w, h: r.h,
                cx: Math.round(r.x + r.w / 2), cy: Math.round(r.y + r.h / 2),
                visible: e.item.visible !== false
            };
            if (e.hit) {
                var h = ui.relRect(e.hit);
                o.hitX = h.x; o.hitY = h.y; o.hitW = h.w; o.hitH = h.h;
                o.hitMatchesVisual = (h.x === r.x && h.y === r.y
                                      && h.w === r.w && h.h === r.h);
                o.hitMin = Math.min(h.w, h.h);
            }
            out.push(o);
        }
        return out;
    }

    // Zones de molette (brief v3 §2) : une par module, sur tout le bloc.
    // Suivies à part des cibles cliquables : ce ne sont pas des boutons.
    property var wheelZones: []

    function trackWheel(name, item) {
        ui.wheelZones.push({ name: name, item: item });
    }

    function untrackWheel(item) {
        var out = [];
        for (var i = 0; i < ui.wheelZones.length; i++) {
            if (ui.wheelZones[i].item !== item)
                out.push(ui.wheelZones[i]);
        }
        ui.wheelZones = out;
    }

    function dumpWheelZones() {
        var out = [];
        for (var i = 0; i < ui.wheelZones.length; i++) {
            var e = ui.wheelZones[i];
            if (!e.item)
                continue;
            var r = null;
            try {
                r = ui.relRect(e.item);
            } catch (err) {
                continue;
            }
            if (!r || r.w <= 0 || r.h <= 0)
                continue;
            out.push({ name: e.name, x: r.x, y: r.y, w: r.w, h: r.h,
                       cy0: r.y, cy1: r.y + r.h });
        }
        return out;
    }

    // v4 §7/§8 : fermer/ouvrir une popup fait TOUJOURS disparaître
    // l'infobulle (elle décrit une cible qu'on vient de quitter des yeux).
    // Un seul popup à la fois : `popup` est un nom unique, pas un tableau.
    function open(name) {
        ui.windowClass = "";
        ui.windowTitle = "";
        ui.closeMenuContext();
        Tip.hideNow();
        ui.popup = (ui.popup === name) ? "" : name;
    }

    function openWindows(cls, title) {
        ui.windowClass = cls || "";
        ui.windowTitle = title || "";
        ui.closeMenuContext();
        Tip.hideNow();
        ui.popup = "windows";
    }

    // Popup « Ajouter une application » (bouton « + » sous les apps épinglées).
    function openAddApp() {
        ui.windowClass = "";
        ui.windowTitle = "";
        ui.closeMenuContext();
        Tip.hideNow();
        ui.popup = (ui.popup === "addapp") ? "" : "addapp";
    }

    // Menu d'une app (clic droit) : « Détacher » / « Épingler » + « Fenêtres ».
    function openAppMenu(kind, id, cls, desktop, title) {
        ui.windowClass = "";
        ui.windowTitle = "";
        ui.appMenuKind = kind || "";
        ui.appMenuId = id || "";
        ui.appMenuClass = cls || "";
        ui.appMenuDesktop = desktop || "";
        ui.appMenuTitle = title || "";
        Tip.hideNow();
        ui.popup = "appmenu";
    }

    function closeMenuContext() {
        ui.appMenuKind = "";
        ui.appMenuId = "";
        ui.appMenuClass = "";
        ui.appMenuDesktop = "";
        ui.appMenuTitle = "";
    }

    function close() {
        Tip.hideNow();
        ui.popup = "";
        ui.windowClass = "";
        ui.windowTitle = "";
        ui.closeMenuContext();
    }

    function isOpen(name) {
        return ui.popup === name;
    }

    // ── Actions enregistrées par les modules ─────────────────────────────
    // `qs ipc call bar action <nom>` exécute EXACTEMENT le code du bouton
    // (pas une simulation d'événement souris, absente sur ce poste).
    property var actions: ({})

    function registerAction(name, fn) {
        var a = ui.actions;
        a[name] = fn;
        ui.actions = a;
    }

    function runAction(name) {
        var fn = ui.actions[name];
        if (typeof fn !== "function") {
            Hypr.miss("action inconnue : " + name);
            return false;
        }
        fn();
        return true;
    }
}
