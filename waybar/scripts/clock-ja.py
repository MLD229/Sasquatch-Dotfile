#!/usr/bin/env python3
"""clock-ja.py — horloge japonaise pour waybar (Sasquatch-Dotfile).

Affiche l'heure en hiragana dans la barre (kif absolu du projet UI japonaise)
et un tooltip avec épellation + traduction + date + mini calendrier.

Sortie waybar custom module : {"text": "...", "tooltip": "..."} sur stdout.
Spec momo : hiragana surtout, kanji rarement, traduction TOUJOURS dans le tooltip.
"""
import datetime
import json
import sys

# --- Tables de lecture (heure) ---
HOURS = {
    0: "れいじ", 1: "いちじ", 2: "にじ", 3: "さんじ", 4: "よじ", 5: "ごじ",
    6: "ろくじ", 7: "しちじ", 8: "はちじ", 9: "くじ", 10: "じゅうじ",
    11: "じゅういちじ", 12: "じゅうにじ", 13: "じゅうさんじ", 14: "じゅうよじ",
    15: "じゅうごじ", 16: "じゅうろくじ", 17: "じゅうしちじ", 18: "じゅうはちじ",
    19: "じゅうくじ", 20: "にじゅうじ", 21: "にじゅういちじ", 22: "にじゅうにじ",
    23: "にじゅうさんじ",
}

# Minutes : 0 → "" (on dit juste じ), sinon lecture complète
MIN_UNITS = {
    0: "", 1: "いっぷん", 2: "にふん", 3: "さんぷん", 4: "よんぷん", 5: "ごふん",
    6: "ろっぷん", 7: "ななふん", 8: "はっぷん", 9: "きゅうふん",
}
MIN_TENS = {1: "じゅう", 2: "にじゅう", 3: "さんじゅう", 4: "よんじゅう", 5: "ごじゅう"}


def minutes_ja(m: int) -> str:
    """Lecture des minutes : 35 → さんじゅうごふん ; 0 → ''."""
    if m == 0:
        return ""
    tens, units = divmod(m, 10)
    return MIN_TENS.get(tens, "") + MIN_UNITS[units]


# --- Table de lecture (date) ---
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
WEEKDAYS_KANJI = ["月", "火", "水", "木", "金", "土", "日"]


def calendar_text(year: int, month: int) -> str:
    """Mini calendrier du mois : lignes de jours, aujourd'hui marqué entre [ ]."""
    cal = __import__("calendar").Calendar(firstweekday=0)
    lines = []
    for week in cal.monthdayscalendar(year, month):
        cells = []
        for d in week:
            if d == 0:
                cells.append("  ")
            elif d == datetime.date.today().day:
                cells.append(f"[{d:2d}]")
            else:
                cells.append(f" {d:2d}")
        lines.append(" ".join(cells).rstrip())
    return "\n".join(lines)


def main():
    now = datetime.datetime.now()
    h_ja = HOURS[now.hour]
    m_ja = minutes_ja(now.minute)
    time_ja = f"{h_ja} {m_ja}".strip() if m_ja else h_ja

    date_ja = f"{MONTHS[now.month]} {DAYS[now.day]}"
    wd = WEEKDAYS[now.weekday()]
    wd_k = WEEKDAYS_KANJI[now.weekday()]

    text = f"󰥔  {time_ja}"

    # Tooltip : lecture + traduction + date + calendrier
    tooltip = (
        f"{time_ja}  —  {now:%H:%M}\n"
        f"<small>{now:%Y}ねん {now.month}がつ {now.day}にち  ({wd_k})  —  {now:%d %B %Y}</small>\n\n"
        f"<tt>{calendar_text(now.year, now.month)}</tt>"
    )

    print(json.dumps({"text": text, "tooltip": tooltip}))
    sys.stdout.flush()


if __name__ == "__main__":
    main()
