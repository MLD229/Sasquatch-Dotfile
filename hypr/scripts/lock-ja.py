#!/usr/bin/env python3
"""
lock-ja.py — heure et date japonaises pour hyprlock (Sasquatch-Dotfile).

Usage (depuis hyprlock.conf) :
    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py time
    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py date

Sortie :
  * time : markup Pango — nombres en couleur claire du label (lue dans
    hyprlock.conf, suit la palette dynamique), suffixes じ/ふん en TON PLUS
    FONCÉ (même teinte, luminance réduite). Ex : じゅうにじ さんじゅうごふん
    → じゅうに[clair] じ[foncé] さんじゅうご[clair] ふん[foncé].
  * date : hiragana pur (pas de traduction).

Markup Pango dans les cmd : hyprlock v0.9.6 le REND (vérifié par capture
pendant le lock — spans foreground détectés par pixels). Seul
`<span size=...>` a cassé le lock (reverté) — ne PAS utiliser size,
les couleurs passent.

La police hyprlock DOIT être Noto Sans CJK JP (JetBrains Mono n'a pas les
hiragana → tofu).
"""
import colorsys
import datetime
import json
import os
import re
import sys

HYPPLOCK_CONF = os.path.expanduser("~/.config/hypr/hyprlock.conf")
FG_FALLBACK = "d5cfcb"      # si le label time n'est pas trouvé
SUF_DELTA = 0.35            # réduction de luminance des suffixes (réglable)
SETTINGS_JSON = os.path.expanduser("~/.config/settings/settings.json")


def ui_lang():
    """Langue mémorisée dans settings.json : "ja" (défaut) ou "fr".
    Relue à chaque exécution (hyprlock lance ce script 1×/s) → le toggle du
    panneau prend effet au prochain lock, sans toucher hyprlock.conf."""
    try:
        with open(SETTINGS_JSON, encoding="utf-8") as f:
            data = json.load(f)
        mode = (data or {}).get("lang", {}).get("mode")
        return mode if mode in ("ja", "fr") else "ja"
    except Exception:
        return "ja"


# Tables françaises (hardcodées : la locale Python n'est pas initialisée)
MONTHS_FR = {
    1: "janvier", 2: "février", 3: "mars", 4: "avril", 5: "mai", 6: "juin",
    7: "juillet", 8: "août", 9: "septembre", 10: "octobre", 11: "novembre",
    12: "décembre",
}
WEEKDAYS_FR = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

# ── Tables de lecture (synchronisées avec wallclock-ja.py / clock-ja.py) ──
HOURS = {
    0: "れいじ", 1: "いちじ", 2: "にじ", 3: "さんじ", 4: "よじ", 5: "ごじ",
    6: "ろくじ", 7: "しちじ", 8: "はちじ", 9: "くじ", 10: "じゅうじ",
    11: "じゅういちじ", 12: "じゅうにじ", 13: "じゅうさんじ", 14: "じゅうよじ",
    15: "じゅうごじ", 16: "じゅうろくじ", 17: "じゅうしちじ", 18: "じゅうはちじ",
    19: "じゅうくじ", 20: "にじゅうじ", 21: "にじゅういちじ", 22: "にじゅうにじ",
    23: "にじゅうさんじ",
}
MIN_UNITS = {
    0: "", 1: "いっぷん", 2: "にふん", 3: "さんぷん", 4: "よんぷん", 5: "ごふん",
    6: "ろっぷん", 7: "ななふん", 8: "はっぷん", 9: "きゅうふん",
}
MIN_TENS = {1: "じゅう", 2: "にじゅう", 3: "さんじゅう", 4: "よんじゅう", 5: "ごじゅう"}

# Variantes SPLIT (nombre / suffixe) pour colorer じ et ふん/ぷん à part
HOURS_NUM = {
    0: "れい", 1: "いち", 2: "に", 3: "さん", 4: "よ", 5: "ご",
    6: "ろく", 7: "しち", 8: "はち", 9: "く", 10: "じゅう",
    11: "じゅういち", 12: "じゅうに", 13: "じゅうさん", 14: "じゅうよ",
    15: "じゅうご", 16: "じゅうろく", 17: "じゅうしち", 18: "じゅうはち",
    19: "じゅうく", 20: "にじゅう", 21: "にじゅういち", 22: "にじゅうに",
    23: "にじゅうさん",
}
HOUR_SUFFIX = "じ"
MIN_UNITS_NUM = {
    0: "", 1: "いっ", 2: "に", 3: "さん", 4: "よん", 5: "ご",
    6: "ろっ", 7: "なな", 8: "はっ", 9: "きゅう",
}
MIN_SUFFIX = {1: "ぷん", 2: "ふん", 3: "ぷん", 4: "ぷん", 5: "ふん",
              6: "ぷん", 7: "ふん", 8: "ぷん", 9: "ふん"}

MONTHS = {
    1: "いちがつ", 2: "にがつ", 3: "さんがつ", 4: "しがつ", 5: "ごがつ",
    6: "ろくがつ", 7: "しちがつ", 8: "はちがつ", 9: "くがつ", 10: "じゅうがつ",
    11: "じゅういちがつ", 12: "じゅうにがつ",
}
DAYS = {
    1: "ついたち", 2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか",
    6: "むいか", 7: "なのか", 8: "ようか", 9: "ここのか", 10: "とおか",
    11: "じゅういちにち", 12: "じゅうににち", 13: "じゅうさんにち", 14: "じゅうよっか",
    15: "じゅうごにち", 16: "じゅうろくにち", 17: "じゅうしちにち", 18: "じゅうはちにち",
    19: "じゅうくにち", 20: "はつか", 21: "にじゅういちにち", 22: "にじゅうににち",
    23: "にじゅうさんにち", 24: "にじゅうよっか", 25: "にじゅうごにち",
    26: "にじゅうろくにち", 27: "にじゅうしちにち", 28: "にじゅうはちにち",
    29: "にじゅうくにち", 30: "さんじゅうにち", 31: "さんじゅういちにち",
}
WEEKDAYS = ["げつようび", "かようび", "すいようび", "もくようび", "きんようび", "どようび", "にちようび"]


def minutes_ja(m):
    if m == 0:
        return ""
    tens, units = divmod(m, 10)
    if units == 0:
        # Dizaine exacte : じゅう → じゅっ devant ぷん (じゅっぷん, PAS じゅうぷん)
        return MIN_TENS[tens].replace("じゅう", "じゅっ") + "ぷん"
    return MIN_TENS.get(tens, "") + MIN_UNITS[units]


def time_ja(now):
    h = HOURS[now.hour]
    m = minutes_ja(now.minute)
    return f"{h} {m}".strip() if m else h


def date_ja(now):
    return f"{MONTHS[now.month]} {DAYS[now.day]}（{WEEKDAYS[now.weekday()]}）"


def read_label_color():
    """Couleur du label time dans hyprlock.conf (rgba hex sans alpha) — lue
    à chaque appel → suit la palette dynamique (theme-apply.py réécrit le
    fichier). Fallback dur si introuvable."""
    try:
        with open(HYPPLOCK_CONF) as f:
            conf = f.read()
        m = re.search(
            r"text = cmd\[update:\d+\][^\n]*lock-ja\.py time.*?color = rgba\(([0-9a-fA-F]{6})",
            conf, re.S)
        if m:
            return m.group(1).lower()
    except OSError:
        pass
    return FG_FALLBACK


def darker_hex(hex6, delta=SUF_DELTA):
    """Version plus foncée (même teinte/saturation, luminance − delta,
    clampée ≥ 0.12 pour rester lisible)."""
    r, g, b = (int(hex6[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l2 = max(0.12, min(1.0, l - delta))
    r2, g2, b2 = colorsys.hls_to_rgb(h, l2, s)
    return "#{:02x}{:02x}{:02x}".format(*(int(round(c * 255)) for c in (r2, g2, b2)))


def time_ja_markup(now, fg, suf):
    """Heure en markup Pango : nombres en fg, suffixes じ/ふん en suf.
    Groupes COLLÉS (nombre+suffixe), espace seulement entre groupes."""
    def sp(text, color):
        if not color.startswith("#"):
            color = "#" + color
        return f'<span foreground="{color}">{text}</span>'

    out = sp(HOURS_NUM[now.hour], fg) + sp(HOUR_SUFFIX, suf)
    m = now.minute
    if m:
        tens, units = divmod(m, 10)
        num = MIN_TENS.get(tens, "") + MIN_UNITS_NUM[units]
        out += sp(" ", fg) + sp(num, fg)
        if units:
            out += sp(MIN_SUFFIX[units], suf)
    return out


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "time"
    now = datetime.datetime.now()

    # Mode FR : heure "14:30" (markup couleur = même format que JA) et date
    # "jeudi 20 août" (texte brut, comme la date JA).
    if ui_lang() == "fr":
        if mode == "time":
            fg = read_label_color()
            print(f'<span foreground="#{fg}">{now:%H:%M}</span>')
        elif mode == "date":
            print(f"{WEEKDAYS_FR[now.weekday()]} {now.day} {MONTHS_FR[now.month]}")
        else:
            print(f"{now:%H:%M}")
        return

    if mode == "time":
        fg = read_label_color()
        suf = darker_hex(fg)
        print(time_ja_markup(now, fg, suf))
    elif mode == "date":
        print(date_ja(now))
    else:
        print(time_ja(now))


if __name__ == "__main__":
    main()
