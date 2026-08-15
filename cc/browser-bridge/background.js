// Sasquatch CC Bridge — service worker (background)
// Reçoit le now-playing du content script et le POST vers le CC.
// La réponse du CC contient la commande éventuelle (toggle/seek/…) que
// le content script appliquera à l'élément media.

const ENDPOINT = "http://127.0.0.1:8765/api/music/web";

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.type !== "nowplaying") return;
  fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(msg.payload),
  })
    .then((r) => r.json())
    .then((resp) => sendResponse({ command: resp && resp.command }))
    .catch(() => sendResponse({}));
  return true; // réponse asynchrone
});
