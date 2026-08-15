// Sasquatch CC Bridge — content script
// Injecté dans chaque page : détecte l'élément <video>/<audio> dominant,
// collecte le now-playing (titre, artiste, image, durée, position) et
// l'envoie au service worker qui POST vers le CC. Applique aussi les
// commandes reçues (toggle/seek/next…) à l'élément media.

const TOKEN = "sasquatch-cc-bridge";
const TICK_MS = 1000;

let media = null;

function scoreMedia(el) {
  let s = 0;
  if (!el.paused && !el.ended) s += 100;
  const d = el.duration;
  if (isFinite(d) && d > 0) s += 50;
  if (el.tagName === "VIDEO") s += 10;
  const r = el.getBoundingClientRect();
  if (r.width * r.height > 10000) s += 20;
  return s;
}

function findMedia() {
  const all = [...document.querySelectorAll("video, audio")];
  if (!all.length) return null;
  all.sort((a, b) => scoreMedia(b) - scoreMedia(a));
  return all[0];
}

function og(prop) {
  const m = document.querySelector(`meta[property="${prop}"], meta[name="${prop}"]`);
  return m ? m.getAttribute("content") : null;
}

function getPlayerName() {
  const h = location.hostname.toLowerCase();
  if (h.includes("youtube")) return "YouTube";
  if (h.includes("netflix")) return "Netflix";
  if (h.includes("spotify")) return "Spotify";
  if (h.includes("twitch")) return "Twitch";
  if (h.includes("soundcloud")) return "SoundCloud";
  if (h.includes("dailymotion")) return "Dailymotion";
  return h.replace(/^www\./, "") || "navigateur";
}

function getTitle() {
  const t = og("og:title");
  if (t) return t.trim();
  const raw = document.title;
  if (raw) return raw.replace(/\s*[-–|]\s*[^-–|]*$/, "").trim();
  return null;
}

function getArtist() {
  const a = document.querySelector('link[itemprop="author"], meta[itemprop="author"]');
  if (a) return (a.getAttribute("content") || "").trim() || null;
  return null;
}

function getImage() {
  // YouTube expose og:image = miniature hqdefault/maxres ; sinon poster du media.
  return og("og:image") || (media && media.poster) || null;
}

function collect() {
  media = findMedia();
  if (!media) return; // aucune piste → on n'envoie rien (la source devient stale)

  // Chromium/Brave expose un MPRIS NATIF quand la page utilise la MediaSession
  // API (navigator.mediaSession.metadata défini — YouTube, Spotify Web…).
  // Dans ce cas, playerctl voit déjà la lecture : pousser le bridge en plus
  // créerait un doublon côté serveur (source web IGNORÉE quand un MPRIS est
  // actif, mais inutile d'envoyer). Le bridge ne sert que pour les sites
  // SANS MediaSession (lecteurs <video> custom).
  if (navigator.mediaSession && navigator.mediaSession.metadata) return;

  const dur = isFinite(media.duration) && media.duration > 0 ? media.duration : 0;
  const pos = media.currentTime || 0;
  const playing = !media.paused && !media.ended && dur > 0;

  chrome.runtime.sendMessage({
    type: "nowplaying",
    payload: {
      token: TOKEN,
      player: getPlayerName(),
      title: getTitle(),
      artist: getArtist(),
      album: null,
      art: getImage(),
      duration: Math.round(dur * 1000) / 1000,
      position: pos,
      playing: playing,
      paused: media.paused,
      url: location.href,
    },
  }, (resp) => {
    if (resp && resp.command) applyCommand(resp.command);
  });
}

function applyCommand(cmd) {
  if (!cmd || !media) return;
  switch (cmd.type) {
    case "toggle":
      if (media.paused) media.play().catch(() => {});
      else media.pause();
      break;
    case "play":
      media.play().catch(() => {});
      break;
    case "pause":
      media.pause();
      break;
    case "stop":
      media.pause();
      try { media.currentTime = 0; } catch (e) {}
      break;
    case "seek":
      if (typeof cmd.pos === "number") {
        try { media.currentTime = cmd.pos; } catch (e) {}
      }
      break;
    case "next": {
      const n = document.querySelector(".ytp-next-button");
      if (n) n.click();
      break;
    }
    case "prev": {
      const p = document.querySelector(".ytp-prev-button");
      if (p) p.click();
      break;
    }
  }
}

setInterval(collect, TICK_MS);
// Premier envoi dès que la page est prête (ne pas attendre 1 s).
setTimeout(collect, 250);
