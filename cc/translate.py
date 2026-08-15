"""Traduction du texte OCR — LibreTranslate (local puis public) avec fallback
Google GTX (sans clé). Priorité :
  1. LibreTranslate local (http://127.0.0.1:5000) si un serveur tourne ;
  2. Instances publiques LibreTranslate (fiabilité moyenne) ;
  3. Google GTX (endpoint gratuit non-officiel, très fiable, sans clé).

Chaque backend a un timeout court : la traduction ne doit jamais bloquer le
serveur du CC au-delà de quelques secondes (le OCR prend déjà ~2-5 s).
"""

import json
import urllib.parse
import urllib.request

from config import (TRANSLATE_LOCAL_URL, TRANSLATE_PUBLIC_URLS, TRANSLATE_GTX_URL,
                    TRANSLATE_TIMEOUT, TRANSLATE_MAX_LEN)


def _post_lt(url, text, target):
    """POST JSON {q, source:auto, target} → {"translatedText": ...}."""
    payload = json.dumps({
        "q": text, "source": "auto", "target": target, "format": "text",
    }).encode("utf-8")
    req = urllib.request.Request(
        url, data=payload,
        headers={"Content-Type": "application/json",
                 "User-Agent": "sasquatch-cc/1.0"},
    )
    with urllib.request.urlopen(req, timeout=TRANSLATE_TIMEOUT) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    out = (data.get("translatedText") or "").strip()
    if out and out != text:
        return out
    raise RuntimeError("réponse vide ou identique")


def _get_gtx(text, target):
    """GET translate_a/single?client=gtx → segments concaténés."""
    url = ("%s?client=gtx&sl=auto&tl=%s&dt=t&q=%s"
           % (TRANSLATE_GTX_URL, target, urllib.parse.quote(text)))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=TRANSLATE_TIMEOUT) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    parts = []
    for seg in data[0]:
        if seg and seg[0]:
            parts.append(seg[0])
    out = "".join(parts).strip()
    if out:
        return out
    raise RuntimeError("réponse vide")


def translate(text, target=None, max_len=TRANSLATE_MAX_LEN):
    """Traduit `text` vers `target` (défaut : TRANSLATE_TARGET).

    Retourne {"ok": True, "engine": ..., "translation": ...} ou
            {"ok": False, "error": ..., "errors": [...]}.
    """
    if not text or not text.strip():
        return {"ok": False, "error": "texte vide"}
    from config import TRANSLATE_TARGET
    if target is None:
        target = TRANSLATE_TARGET
    text = text.strip()[:max_len]

    errors = []

    # 1) LibreTranslate local (self-hosted — l'option la plus propre)
    try:
        return {"ok": True, "engine": "libretranslate-local",
                "translation": _post_lt(TRANSLATE_LOCAL_URL, text, target)}
    except Exception as e:
        errors.append("local: %s" % e)

    # 2) Instances publiques LibreTranslate
    for url in TRANSLATE_PUBLIC_URLS:
        try:
            return {"ok": True, "engine": "libretranslate-public",
                    "translation": _post_lt(url, text, target)}
        except Exception as e:
            errors.append("public: %s" % e)

    # 3) Fallback Google GTX
    try:
        return {"ok": True, "engine": "google-gtx",
                "translation": _get_gtx(text, target)}
    except Exception as e:
        errors.append("gtx: %s" % e)

    return {"ok": False, "error": "tous les backends de traduction ont échoué",
            "errors": errors}
