# SPEC microcopie + page Outils (arbitrée par Asuka, avis ChatGPT trié point par point)

Référence pour rin. S'applique APRÈS le brief `BRIEF-rin-widgets-polish.md` : mêmes interdits §9.

## Les 5 règles (transversales)

1. **Parler de l'usage, jamais de la technologie.** « Son coupé », pas « mute » ; jamais `MPRIS`,
   `open-meteo`, `wpctl`, `makoctl`, ni un chemin de fichier.
2. **Distinguer trois états** : `zéro` (0 % est une mesure), `non mesuré` (donnée absente),
   `indisponible` (impossible d'obtenir la donnée, avec la raison et l'action).
3. **Une information = un seul emplacement.** Pas de doublon titre/sous-titre/badge/message vide.
4. **Chaque état se comprend seul**, sans connaître le fonctionnement du widget.
5. **Préférer une action ou une durée concrète** : « Réessayer », « il y a 4 min », « en cours… ».

## Microcopie par widget

Chaque ligne : `normal` puis `compact` quand il est plus court. Jamais de phrase longue dans une carte
compacte (220×64) : elle est tronquée et devient du bruit.

| Widget | Titre | Sous-titre / corps | Vide | Chargement | Indisponible |
|---|---|---|---|---|---|
| media | *titre du morceau* | artiste · nom du lecteur (`Brave`, `MPD`, `Audio système`) | `Rien en lecture` / `Aucun lecteur` | `Recherche d'un lecteur…` | `Aucun lecteur disponible` |
| weather | `Météo` | `Lyon · plutôt dégagé` | `Météo indisponible` | `Récupération…` | `Météo indisponible` |
| resources | `Utilisation` | `Processeur · Mémoire · Carte graphique` | `Non mesuré` (par anneau) | `Mesure…` | `Mesure indisponible` |
| tasks | `Mes tâches` | `2 restantes` | `Aucune tâche` / `—` | `Chargement…` | `Tâches indisponibles` |
| volume | `Son` | `51 %` · `Son coupé` | `—` | `Lecture…` | `Réglage du son indisponible` |
| (luminosité, même widget) | `Luminosité` | `95 %` | `—` | `Lecture…` | `Réglage indisponible` |
| battery | `Batterie` | `100 %` seul · `En charge` | `Batterie non détectée` | `Vérification…` | `Batterie indisponible` |
| playlist | `Ma musique` | `0 morceau` (accord) | `Liste vide` (UN seul message) | `Chargement…` | `Liste indisponible` |
| calendar | `Calendrier` | `novembre 2026` | `Rien de prévu` | `Chargement…` | `Calendrier indisponible` |
| connectivity | `Connexions` | `Wi-Fi · wlan0` / `Bluetooth · Activé` (une info par ligne) | `Aucune connexion` | `Vérification…` | `Gestion du réseau indisponible` |
| toggles | `Modes rapides` | libellés courts : `Ne pas déranger` / `Flou` / `Mode nuit` / `Mode léger` | `—` | `Activation…` | `Indisponible` + raison + `sudo pacman -S …` |
| notifications | `Notifications` | `3 nouvelles` | `Aucune notification` | `Chargement…` | `Notifications indisponibles` |
| workspaces | `Bureaux` | numéro + `n fenêtres` | `Aucune fenêtre` | `Chargement…` | `Bureaux indisponibles` |
| apps | `Favoris` | nom de l'app | `Aucun favori` | `Chargement…` | `Application introuvable` + `Retirer` |
| notes | `Mes notes` | `2 notes` | `Aucune note` | `Chargement…` | `Notes indisponibles` |

Décisions ponctuelles (refus de la version longue de ChatGPT, gardée courte) :
- **Media** : le titre reste le morceau, pas « En lecture » (le contexte est évident dans la carte).
- **Notifications** : un titre qui est un nom de fichier ou une chaîne technique (`notify-send-2026…`)
  devient `Capture d'écran 20:28` (regex sur horodatage), sinon `Notification` + le corps réel en dessous.
- **Apps introuvable** : jamais de suppression silencieuse — pastille initiale + action `Retirer`.
- **Battery** : `100 %` seul, jamais `pleine` en plus.

## Page Outils — structure imposée (3 blocs, pas 4)

Pas de bloc « Recherche » : le CC n'a pas d'outil de recherche, ne pas en inventer un.

En-tête : titre `Outils`, sous-titre `Capturer, lire une image, traduire.`

**01 · Capture d'écran** — « Enregistrer une image de l'écran, d'une fenêtre ou d'une zone. »
- bouton principal `Capturer` → puis choix `Zone` / `Fenêtre` / `Écran entier` (les 3 existent déjà dans le code) ;
- pendant : `Sélectionne une zone…` puis `Capture en cours…` ; succès : `Capture enregistrée.` ;
- échec : `Impossible de réaliser la capture. Réessaie.` ;
- dépendance : `La capture n'est pas installée.` + `sudo pacman -S grim slurp`.

**02 · Lire une image** — « Sélectionner une zone pour en extraire le texte et chercher des images proches. »
- bouton principal `Sélectionner une zone` ;
- pendant : `Sélectionne une zone…`, puis `Lecture du texte…`, puis `Recherche d'images…` ;
- succès : deux sections séparées `Texte détecté` et `Images proches` ;
- échec OCR : `Aucun texte détecté dans cette sélection.` ; échec recherche : `La recherche a échoué. Réessaie.` ;
- dépendance : `La lecture de texte n'est pas installée.` + `sudo pacman -S tesseract`.

**03 · Traduire** — « Écrire ou coller un texte pour le traduire. »
- champ `Texte à traduire…`, choix de langue cible, bouton `Traduire` ;
- pendant : `Traduction en cours…` ; succès : bloc `Traduction` + bouton `Copier` ;
- texte vide : `Saisis un texte à traduire.` ; échec : `La traduction a échoué. Réessaie.` ;
- service absent : `Le service de traduction est indisponible.`

**Règles de page** : un bloc = une action principale ; les actions secondaires n'apparaissent qu'une
fois pertinentes ; le résultat s'affiche SOUS son bloc ; une erreur reste dans son bloc (pas de
notification fugace) ; une dépendance manquante ne désactive QUE son bloc.

## Style

Mêmes tokens que le board (`Theme.fill`, halo `MultiEffect`, `radiusCard`, `spacing`) : après ce
passage, un bloc de la page Outils et une carte du board doivent être indiscernables.
