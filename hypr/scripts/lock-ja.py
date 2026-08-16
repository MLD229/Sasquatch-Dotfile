#!/usr/bin/env python3
"""
lock-ja.py — heure et date japonaises pour hyprlock (Sasquatch-Dotfile).

Usage (depuis hyprlock.conf) :
    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py time
    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py date

Sortie (hiragana pur, PAS de traduction — spec momo 2026-08-16) :
  * time : れいじ にじゅうよんぷん
  * date : はちがつ じゅうろくにち（にちようび）

La police hyprlock DOIT être Noto Sans CJK JP (JetBrains Mono n'a pas les
hiragana → tofu). Pas de balise Pango : hyprlock les gère mal (lock cassé
le 15/08 — cause du revert).
"""
import datetime
import sys

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
    return MIN_TENS.get(tens, "") + MIN_UNITS[units]


def time_ja(now):
    h = HOURS[now.hour]
    m = minutes_ja(now.minute)
    return f"{h} {m}".strip() if m else h


def date_ja(now):
    return f"{MONTHS[now.month]} {DAYS[now.day]}（{WEEKDAYS[now.weekday()]}）"


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "time"
    now = datetime.datetime.now()
    if mode == "time":
        print(time_ja(now))
    elif mode == "date":
        print(date_ja(now))
    else:
        print(time_ja(now))


if __name__ == "__main__":
    main()
