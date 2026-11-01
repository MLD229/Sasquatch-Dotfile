# Rapport rin — tranche « widgets » (brief polish)

Date : 2026-11-01 12:5x CET · Repo : `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`)
Verdict : **§0 échoue → aucun widget touché. Rien de corrigé côté QML, par construction.**

## §0 — Porte d'entrée : le backend est périmé

| # | Contrôle | Action | Preuve |
|---|---|---|---|
| 0.1 | `curl -o /dev/null -w "%{http_code}" localhost:8765/api/widgets` | constat, aucune modification | `404` |
| 0.2 | idem `/api/notes` | constat | `404` |
| 0.3 | Qui tient le port ? | `ps -eo pid,user,etime,cmd \| grep server.py` | `1495487 work 13:34 /usr/bin/python3 /home/work/.config/cc/server.py` → **compte `work`**, pas momo |
| 0.4 | Le port répond-il notre API ? | 14 routes sondées (`/api/state`, `/api/media`, `/api/perf`, `/api/widgets`, `/api/notes`…) | **404 partout** ; seul `/` répond `<h1>SasquatchCC</h1><p>Serveur actif.</p>` → backend minimal, pas notre API |
| 0.5 | Notre service tourne-t-il ? | `systemctl --user status sasquatch-cc` | `activating (auto-restart)`, `Result: exit-code`, **restart counter 101** |
| 0.6 | Pourquoi il meurt ? | `journalctl --user -u sasquatch-cc` | `OSError: [Errno 98] Address already in use` sur `ThreadingHTTPServer((HOST, PORT))` |
| 0.7 | Le code du repo est-il en cause ? | `grep -n api/widgets cc/server.py` | routes présentes : L447 / L459 / L584 / L608 ; 53 routes `/api/…` |
| 0.8 | `~/.config/cc` pointe-t-il bien le repo ? | `readlink -f` + `cmp` | `server.py identique au repo` (symlink intact) |
| 0.9 | **Test décisif** : notre `server.py` sur un port libre (58641, config.PORT patché, process tué après) | `GET /api/widgets` | **`200`** `{"ok": true, "revision": 67, "data": {"version": 1, …, "instances": [{"id": "clock-cc"…]}}` |
| 0.10 | idem `/api/notes` | `GET /api/notes` | **`200`** `{"ok": true, "notes": [], "count": 0, "file": "/home/momo/.config/cc/notes.json"}` |

Conclusion : **le code et les routes sont sains ; c'est le port 8765 qui est squatté par le backend du compte
`work`.** Les widgets « morts » sont un symptôme du port, exactement le cas prévu par §0. Corriger du QML ici
aurait consisté à rafistoler des fichiers sains → non fait volontairement.

## §1, §2, §5.1, §5.3 — statut : NON EXÉCUTÉS (bloqués par §0)

| Élément | Statut | Raison |
|---|---|---|
| §1 règle de lisibilité | non commencé | toute vérification « valeur affichée = valeur HTTP » est impossible, l'API répond 404 |
| §2 les 14 widgets | non commencé | idem — aucun diagnostic à faire sur du QML qui n'a jamais reçu de données |
| §5.1 livrable widgets | non livré | dépend de §2 |
| §5.3 `cc/widgets/tests/polish.sh` | non écrit | le harnais compare l'affichage à la réponse HTTP ; sans `200` il ne peut rien prouver. L'écrire maintenant = code à l'aveugle contre une API morte |
| §3 Système/Outils | **hors tranche** (consigne explicite) | non touché, comme demandé |

Aucun fichier QML ni script du repo n'a été modifié. Preuve par horodatage (`find . -newermt "2026-11-01 12:51:00"`, début de mon run) :
seuls `docs/RAPPORT-rin-widgets-S0-port.md` (ce rapport) et deux fichiers de briefs déjà présents apparaissent.
Les mtimes des widgets (MediaWidget 12:08, BatteryWidget 12:22, server.py 12:36) sont tous **antérieurs** à mon
run : le `git diff --stat` non vide sur `cc/widgets` est le travail non commité *antérieur* de momo, pas le mien.

## Ce qui reste — bloqué sur une action de momo (droits root)

Le process fautif appartient au compte `work`, momo ne peut pas le tuer. À lancer par momo :

```bash
systemctl --user stop sasquatch-cc            # coupe la boucle de restart (101 itérations)
sudo kill 1495487                             # libère 8765  (relancer ps si le PID a changé)
systemctl --user start sasquatch-cc
curl -s -o /dev/null -w "%{http_code}\n" localhost:8765/api/widgets   # attendu : 200
curl -s -o /dev/null -w "%{http_code}\n" localhost:8765/api/notes     # attendu : 200
```

Si `sudo kill` ne suffit pas (service user de `work` qui le relance) : `sudo systemctl --machine=work@.host --user stop` côté compte `work`, ou désactiver son unité `sasquatch-cc` / `cc` chez `work`.

Une fois `200` + `200`, la tranche §1 + §2 + §5.1/§5.3 est exécutable telle quelle, sans autre préalable.

## Ce que seul momo peut valider à l'écran

1. Après libération du port : le board affiche des valeurs réelles (pas `—` partout) — c'est le signal que le bon backend sert l'UI.
2. Le crash-loop disparaît : `systemctl --user is-active sasquatch-cc` → `active` stable.
3. Rendu visuel réel des 14 widgets (lisibilité, copy française) — non vérifiable tant que l'API répond 404.

## Notes pour la suite

- Ne pas réutiliser `pkill -f "server.py"` : le motif matche aussi le shell appelant (vécu ici, shell tué en SIGTERM). Tuer par PID.
- Ports déjà pris sur la machine : 8765 (work), 8766, 8778 — choisir un port libre pour tout test isolé.
- `cc/config.py` : `PORT = 8765` en dur ; un test isolé se fait en patchant `config.PORT` avant `import server`.
