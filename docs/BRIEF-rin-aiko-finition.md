# BRIEF Rin — aiko v2 : passe de FINITION avant commit

Date : 2026-10-29
Auteur : Asuka — demande de momo
Destinataire : Rin

## CONTEXTE
Ton aiko v2 fonctionne (vérifié : 25/25 PASS, cold start 1,22 s, 80 tok/s,
fermeture → 0 process + VRAM rendue). momo demande **une passe de finition**
AVANT le commit git. Ne refais pas l'architecture : corrige, durcis, complète.

## 1. MÉMORISER LE DERNIER MODÈLE CHOISI (demande explicite de momo)
« retenir le dernier modèle choisi genre entre le 3 et 7b à la réouverture »

- Persister **uniquement la PRÉFÉRENCE** (clé `model` = `rapide` | `best`),
  PAS la conversation. La règle « zéro mémoire » reste vraie pour le chat :
  l'historique disparaît à la fermeture.
- Fichier dédié, petit, hors du dépôt : `~/.local/state/aiko/prefs.json`
  (créer le dossier au besoin, écriture atomique : tmp + `os.replace`).
- **Au démarrage** : lire prefs.json → si le profil existe dans `models.json`,
  l'utiliser ; sinon retomber sur `models.json["default"]` (et le dire dans les
  logs techniques, pas dans l'UI).
- **Au changement** dans l'UI : écrire immédiatement prefs.json + tuer le
  process modèle en cours (le prochain message recharge le bon).
- Si le fichier est absent/corrompu/illisible : jamais de crash, on repart sur
  le défaut.
- **README** : documenter noir sur blanc que ce fichier est la SEULE chose
  persistée, et pourquoi (préférence ≠ mémoire de conversation).
- Vérifier que le test « aucune persistance » ne casse pas : il doit maintenant
  vérifier « pas d'historique/état de chat », pas « aucun fichier du tout ».
  Adapte-le et nomme-le clairement.

## 2. CONFLITS ET PROBLÈMES À TRAITER (cherche les vrais, pas des hypothèses)

1. **Double backend** : `aiko.sh` lance `server.py` à la demande ET
   `aiko.service` existe (non activé). Si les deux démarrent → port 8791 pris,
   comportements incohérents. Vérifie et rends ça impossible : une seule source
   de vérité (aiko.sh réutilise un backend déjà là ; le service, s'il tourne,
   est détecté et respecté). Documente le choix.
2. **Port occupé au démarrage** : si 8791/8792 sont déjà pris (autre instance,
   process zombie), message clair au lieu d'un crash silencieux.
3. **Panels Quickshell concurrents** : aiko (Super+N, gauche) et cc/sidebar
   (Super+U, droite). Vérifie qu'ouvrir l'un ne casse pas l'autre, qu'aucun ne
   prend le grab clavier (déjà interdit dans cc/sidebar : pourquoi hyprlock a
   été bloqué), et que deux instances d'aiko ne peuvent pas coexister.
4. **Arrêt pendant le chargement du modèle** : fermer pendant le cold start
   doit tuer proprement et ne pas laisser de process orphelin.
5. **Modèle absent** (fichier GGUF supprimé) : message UI explicite + commande
   de téléchargement, jamais un crash.
6. **`llama-server` absent** : chute propre en CPU n'existe pas si le binaire
   manque → message clair avec la commande d'installation.
7. **qmllint** sort 255 sans message sur ton shell.qml : si c'est dû à
   `pragma ComponentBehavior` ou aux imports Quickshell, documente-le dans le
   README (limite connue) plutôt que de laisser croire à un fichier cassé.
8. Relis `llm.py` / `server.py` pour tout `TODO`, chemin en dur inutile,
   exception avalée sans log, ou fuite de process.

## 3. DÉPENDANCES ET INSTALLATION (à mettre à jour)
- `aiko/installer.sh` doit vérifier ET dire quoi faire, dans cet ordre :
  1. `llama-server` présent (sinon : build Vulkan précompilé OU
     `sudo pacman -S llama-cpp` — préciser que le paquet Arch est **CPU-only**,
     12,8 tok/s contre 80 tok/s en Vulkan) ;
  2. les GGUF dans `~/models/` (3B obligatoire, 7B optionnel) avec la commande
     exacte de téléchargement (bartowski, Q4_K_M) ;
  3. `wl-copy` (bouton copier), `curl`, `python3` ;
  4. le keybind `Super+N` présent dans `hypr/keybinds.conf` (l'ajouter s'il
     manque, sans doublon).
- Mettre à jour **`install.sh` du dépôt** (celui de la racine) : ajouter ce que
  aiko exige (llama-cpp/llama-server, modèles si pertinent) dans le bon groupe
  de paquets, et le lien du service aiko si tu le gardes.
- `README.md` d'aiko : commandes (ouvrir, tester, installer), chiffres mesurés
  (cold start 1,22 s / 1,58 s premier token / 80 tok/s en 3B Vulkan ; 7B 12,2 s
  / 39 tok/s), ce qui est persisté (prefs.json seulement), et les limites.

## 4. VÉRIFICATION (preuves réelles)
- `python3 -m py_compile` sur tous les .py, `bash -n` sur les .sh.
- Relance `tests/lifecycle_test.py` → doit rester **25/25** (adapte le test de
  persistance comme dit au §1).
- **Nouveau test** : changer de modèle → fermer → rouvrir → le modèle choisi
  est bien rechargé (prouve-le avec prefs.json + `/api/health`).
- Preuve « zéro résidu » : `pgrep -x llama-server` = 0 après fermeture.
- Si la session est déverrouillée : capture `grim` du panneau **gauche** et
  regarde-la. Sinon, dis-le (ne prétends pas).

## RÈGLES
- Pas de commit (Asuka/momo valident après ta passe).
- Ne touche pas `cc/sidebar` (l'autre panneau) ni `theme-apply.py`.
- Sois honnête : liste ce qui reste fragile.

## LIVRABLE
Fichiers modifiés, sorties réelles des tests, ce qui a été corrigé (une ligne
par conflit), ce qui n'a pas pu être testé.
