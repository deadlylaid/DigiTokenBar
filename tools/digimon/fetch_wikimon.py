#!/usr/bin/env python3
"""Download the Wikimon pages needed to build the Digimon evolution data.

Raw wikitext goes to tools/digimon/.cache/ (git-ignored). Only the derived data
produced by build_data.py is committed. Wikimon text is CC BY-SA 3.0.

    python3 -I tools/digimon/fetch_wikimon.py                 # reuse cached lists, fetch missing pages
    python3 -I tools/digimon/fetch_wikimon.py --refresh       # re-download everything
    python3 -I tools/digimon/fetch_wikimon.py --refresh-images  # also re-scan all ~78k file names (slow)
"""
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".cache"
PAGES = CACHE / "pages"
API = "https://wikimon.net/api.php"
UA = {"User-Agent": "digimon-tokenbar-data/0.1 (personal, non-commercial; deadlylaid)"}
PAUSE = 0.3

# Color V-Pet devices whose sprites we use. Their pages list evolutions with the VPetEvo template.
DEVICE_PAGES = [
    "Digital Monster COLOR Ver.1", "Digital Monster COLOR Ver.2", "Digital Monster COLOR Ver.3",
    "Digital Monster COLOR Ver.4", "Digital Monster COLOR Ver.5",
    "Digital Monster COLOR Digimon Xros Wars 15th Edition",
    "Pendulum COLOR 1 Nature Spirits", "Pendulum COLOR 2 Deep Savers", "Pendulum COLOR 3 Nightmare Soldiers",
    "Pendulum COLOR 4 Wind Guardians", "Pendulum COLOR 5 Metal Empire", "Pendulum COLOR 6 Saiyu Warriors",
    "Pendulum COLOR 7 Toho Braves", "Pendulum COLOR ZERO Virus Busters",
]
CARD_LIST_PAGE = "Vital Bracelet Series/Memory Cards"


def norm(s):
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", s.lower())


# Sprite file names drop words that article titles keep: "Imperialdramon_dragon" is the article
# "Imperialdramon: Dragon Mode", "Agumon2006" is "Agumon (2006 Anime Version)".
TITLE_SUFFIXES = ("mode", "animeversion", "arm", "perfect", "species", "antibody")


def sprite_key_for_title(title_norm, sprite_keys):
    """Sprite key used by this article: the title itself, or the title minus a known suffix."""
    if title_norm in sprite_keys:
        return title_norm
    for suf in TITLE_SUFFIXES:
        if title_norm.endswith(suf) and title_norm[: -len(suf)] in sprite_keys:
            return title_norm[: -len(suf)]
    return None


def api(params):
    params = dict(params, format="json")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers=UA)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry any network error
            if attempt == 3:
                raise
            print(f"  retry ({e})", file=sys.stderr)
            time.sleep(2 * (attempt + 1))


def paged(params, key, cont_key):
    out, cont = [], {}
    while True:
        d = api(dict(params, **cont))
        out += d["query"][key]
        if "continue" not in d:
            return out
        cont = {cont_key: d["continue"][cont_key], "continue": d["continue"]["continue"]}
        time.sleep(PAUSE)


def image_names(refresh):
    f = CACHE / "wikimon_images.json"
    if f.exists() and not refresh:
        return json.loads(f.read_text())
    print("scanning all Wikimon file names (slow)...")
    names = [i["name"] for i in paged({"action": "query", "list": "allimages", "ailimit": "500", "aiprop": ""},
                                      "allimages", "aicontinue")]
    f.write_text(json.dumps(names))
    return names


def all_titles(refresh):
    f = CACHE / "titles.json"
    if f.exists() and not refresh:
        return json.loads(f.read_text())
    print("listing article titles...")
    titles = [p["title"] for p in paged({"action": "query", "list": "allpages", "apnamespace": "0", "aplimit": "500",
                                         "apfilterredir": "nonredirects"}, "allpages", "apcontinue")]
    f.write_text(json.dumps(titles))
    return titles


def fetch_contents(titles, refresh):
    """Save wikitext for each title to .cache/pages/<norm>.wiki (50 titles per request)."""
    PAGES.mkdir(parents=True, exist_ok=True)
    todo = [t for t in titles if refresh or not (PAGES / f"{norm(t)}.wiki").exists()]
    print(f"pages: {len(titles)} wanted, {len(todo)} to download")
    for i in range(0, len(todo), 50):
        batch = todo[i:i + 50]
        d = api({"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                 "titles": "|".join(batch), "redirects": "1"})
        back = {r["to"]: r["from"] for r in d["query"].get("redirects", [])}
        for p in d["query"]["pages"].values():
            if "revisions" not in p:
                continue
            text = p["revisions"][0]["slots"]["main"]["*"]
            asked = back.get(p["title"], p["title"])
            (PAGES / f"{norm(asked)}.wiki").write_text(text)
        print(f"  {min(i + 50, len(todo))}/{len(todo)}")
        time.sleep(PAUSE)


def main():
    refresh = "--refresh" in sys.argv
    CACHE.mkdir(exist_ok=True)
    names = image_names("--refresh-images" in sys.argv)
    sprite_keys = set()
    for n in names:
        m = re.match(r"(.+?)_vpet_(vb|dmc|dpc)\.(png|gif)$", n, re.I)
        if m:
            sprite_keys.add(norm(m.group(1)))
    titles = all_titles(refresh)
    digimon = [t for t in titles if sprite_key_for_title(norm(t), sprite_keys)]
    print(f"sprite keys: {len(sprite_keys)}, matching article titles: {len(digimon)}")
    fetch_contents(DEVICE_PAGES + [CARD_LIST_PAGE] + digimon, refresh)
    (CACHE / "fetched_at.txt").write_text(time.strftime("%Y-%m-%d"))


if __name__ == "__main__":
    main()
