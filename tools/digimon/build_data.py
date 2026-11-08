#!/usr/bin/env python3
"""Build tools/digimon/data/evolutions.json from the cached Wikimon pages.

Evolution edges come from two places, and we keep only edges whose source is a device
we take sprites from:
  * color V-Pet device pages (VPetEvo template)              -> sources "DMC:<page>" / "DPC:<page>"
  * each Digimon page's "Evolves From" / "Evolves To" lists  -> edges whose reference mentions
    Vital Bracelet, Digital Monster COLOR or Pendulum COLOR ("VB" / "DMC" / "DPC")

    python3 -I tools/digimon/build_data.py
"""
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = HERE / ".cache"
PAGES = CACHE / "pages"
OUT = HERE / "data" / "evolutions.json"
LEVEL_ORDER = ["Digitama", "Baby I", "Baby II", "Child", "Adult", "Perfect", "Ultimate"]
DEVICE_PREFIX = {"Digital Monster COLOR": "DMC", "Pendulum COLOR": "DPC"}


def norm(s):
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]", "", s.lower())


SPRITE_TO_ARTICLE = {}  # sprite file key -> article key (filled in main)


def article_key(k):
    return SPRITE_TO_ARTICLE.get(k, k)


def page(title):
    f = PAGES / f"{norm(title)}.wiki"
    return f.read_text() if f.exists() else None


# ---------- small wikitext helpers ----------

def templates(text, name):
    """Yield the inner text of every {{name ...}} with balanced braces."""
    start = 0
    key = "{{" + name
    while (i := text.find(key, start)) >= 0:
        depth, j = 0, i
        while j < len(text) - 1:
            if text.startswith("{{", j):
                depth += 1
                j += 2
            elif text.startswith("}}", j):
                depth -= 1
                j += 2
                if depth == 0:
                    break
            else:
                j += 1
        yield text[i + len(key):j - 2]
        start = j


def params(inner):
    """Split template params on top-level '|' and return {name: value}."""
    parts, depth, cur, i = [], 0, "", 0
    while i < len(inner):
        two = inner[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            cur += two
            i += 2
            continue
        if two in ("}}", "]]"):
            depth -= 1
            cur += two
            i += 2
            continue
        if inner[i] == "|" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += inner[i]
        i += 1
    parts.append(cur)
    out = {}
    for p in parts:
        if "=" in p:
            k, v = p.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def unlink(s):
    """[[A|B]] -> B, [[A]] -> A, strip bold/italics and simple templates."""
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"'''?", "", s)
    s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    return s.strip()


def device_tags(text):
    tags = set()
    if re.search(r"Vital Bracelet|Vital Hero|Digivice ?-V-", text):
        tags.add("VB")
    if re.search(r"Digital Monster COLOR", text, re.I):
        tags.add("DMC")
    if re.search(r"Pendulum COLOR", text, re.I):
        tags.add("DPC")
    return tags


# ---------- sprites ----------

def sprite_map():
    out = defaultdict(dict)
    for n in json.loads((CACHE / "wikimon_images.json").read_text()):
        m = re.match(r"(.+?)_vpet_(vb|dmc|dpc)\.(png|gif)$", n, re.I)
        if m:
            out[norm(m.group(1))][m.group(2).lower()] = n
    return out


# ---------- device pages (VPetEvo) ----------

def parse_device(title, nodes, edges):
    text = page(title)
    if not text:
        print("missing device page:", title)
        return
    prefix = next(v for k, v in DEVICE_PREFIX.items() if title.startswith(k) or k in title)
    source = f"{prefix}:{title}"
    # split by level sections (==Child== etc.)
    sections = re.split(r"\n==\s*([^=\n]+?)\s*==\s*\n", "\n" + text)
    local = {}  # name norm -> node key within this device
    entries = []
    for k in range(1, len(sections), 2):
        level = sections[k].strip()
        for inner in templates(sections[k + 1], "VPetEvo"):
            p = params(inner)
            if not p.get("n"):
                continue
            img = p.get("i", "").replace(" ", "_")
            m = re.match(r"(.+?)_vpet_", img, re.I)
            key = article_key(norm(m.group(1))) if m else norm(p["n"])
            local[norm(p["n"])] = key
            entries.append((level, key, p))
    for i, (level, key, p) in enumerate(entries):
        # Sprite keys that are not article titles (e.g. Metalgreymonva) map to the article
        # for the same Digimon ("Metal Greymon (Vaccine)" -> MetalGreymon).
        if key not in nodes or "levels" not in nodes[key]:
            alt = norm(re.sub(r"\((Vaccine|Vaccine Species)\)", "", p["n"]))
            if alt in nodes and "levels" in nodes[alt]:
                local = {k: (alt if v == key else v) for k, v in local.items()}
                nodes[alt].setdefault("extra_sprite_keys", set()).add(key)
                key = alt
                entries[i] = (level, key, p)
        n = nodes[key]
        n.setdefault("name", p["n"])
        if level in LEVEL_ORDER:
            n.setdefault("device_levels", set()).add(level)
        if p.get("a"):
            n.setdefault("attributes", set()).add(p["a"])
        for ek in sorted(x for x in p if re.fullmatch(r"e\d+", x)):
            raw = p[ek]
            note = ""
            if ":" in unlink(raw):
                main, note = unlink(raw).split(":", 1)
            else:
                main = unlink(raw)
            for src in [s.strip() for s in main.split("/") if s.strip()]:
                if src.lower().startswith("born from"):
                    continue
                s_norm = norm(src)
                src_key = local.get(s_norm) or next((v for kk, v in local.items() if kk.startswith(s_norm)), s_norm)
                e = edges[(src_key, key)]
                e["sources"].add(source)
                if "jogress" in note.lower():
                    e["jogress"] = note.strip()


# ---------- Digimon pages (Evolves From / To) ----------

def section(text, name):
    m = re.search(r"\n==\s*" + re.escape(name) + r"\s*==\s*\n(.*?)(?=\n==[^=]|\Z)", "\n" + text, re.S)
    return m.group(1) if m else ""


def parse_digimon(title_key, text, nodes, edges):
    n = nodes[title_key]
    info = next(templates(text, "S2"), "")
    p = params(info)
    for k, v in p.items():
        if re.fullmatch(r"l\d+", k) and unlink(v):
            n.setdefault("levels", set()).add(unlink(v))
        if re.fullmatch(r"a\d+", k) and unlink(v):
            n.setdefault("attributes", set()).add(unlink(v))
    # Primary level = the first one listed (l1). Other entries come from specific games.
    first = sorted((int(k[1:]), unlink(v)) for k, v in p.items() if re.fullmatch(r"l\d+", k) and unlink(v))
    if first:
        n["level"] = first[0][1]
    first_attr = sorted((int(k[1:]), unlink(v)) for k, v in p.items() if re.fullmatch(r"a\d+", k) and unlink(v))
    if first_attr:
        n["attribute"] = first_attr[0][1]
    ko = re.search(r"\{\{KOR\}\}\s*\{\{j2\|([^|}]+)", p.get("ol", ""))
    if ko:
        n["ko"] = ko.group(1).strip()
    if p.get("rom"):
        n.setdefault("name", unlink(p["rom"]))

    named = {}
    for m in re.finditer(r'<ref\s+name\s*=\s*"?([^">/]+?)"?\s*>(.*?)</ref>', text, re.S):
        named[m.group(1).strip()] = m.group(2)

    def refs(line):
        out = []
        for m in re.finditer(r'<ref\s+name\s*=\s*"?([^">/]+?)"?\s*/>', line):
            out.append(named.get(m.group(1).strip(), ""))
        out += [m.group(2) for m in re.finditer(r'<ref(\s+name\s*=\s*"?[^">/]+?"?)?\s*>(.*?)</ref>', line, re.S)]
        out += [m.group(1) for m in re.finditer(r"\{\{ref\|(.*?)\}\}(?!\})", line, re.S)]
        return out

    for sec, direction in (("Evolves From", "from"), ("Evolves To", "to")):
        for line in section(text, sec).split("\n"):
            if not line.startswith("*"):
                continue
            m = re.search(r"\[\[([^\]|#]+)(?:\|[^\]]*)?\]\]", line)
            if not m or ":" in m.group(1) or "#" in m.group(0).split("|")[0]:
                continue
            target = norm(m.group(1))
            tags = set()
            for r in refs(line):
                tags |= device_tags(r)
            if not tags:
                continue
            pair = (target, title_key) if direction == "from" else (title_key, target)
            e = edges[pair]
            e["sources"] |= tags
            if line.lstrip("* ").startswith("'''[["):
                e["canon"] = True
            after = line[m.end():m.end() + 120]
            if re.search(r"Jogress|DNA", after):
                e["jogress"] = unlink(after.split("<ref")[0])[:80]
            if "Warp" in after:
                e["warp"] = True


# ---------- Vital Bracelet card rosters ----------

def parse_cards(sprites):
    text = page("Vital Bracelet Series/Memory Cards") or ""
    cards = []
    for row in text.split("\n|-"):
        row = re.sub(r"<!--.*?-->", "", row, flags=re.S)
        roster = re.findall(r"\{\{Sprite\|([^|}]+)\|([^|}]+)", row)
        name = re.search(r"'''([^']+)'''", row)
        if not roster or not name:
            continue
        keys = []
        for f, _ in roster:
            m = re.match(r"(.+?)_vpet_", f.replace(" ", "_"), re.I)
            keys.append(article_key(norm(m.group(1))) if m else norm(f))
        release = re.search(r"\{\{JPN\}\}\s*([A-Z][a-z]+ \d{1,2}, \d{4})", row)
        card_name = re.split(r"\|\||<br|\{\{", name.group(1))[0].strip()
        cards.append({"name": card_name, "release_jp": release.group(1) if release else "",
                      "roster": keys})
    return cards


def main():
    from fetch_wikimon import DEVICE_PAGES, sprite_key_for_title  # noqa: E402  (same folder)
    sprites = sprite_map()
    titles = json.loads((CACHE / "titles.json").read_text())
    sprite_of = {}  # article key -> sprite key
    candidates = defaultdict(list)  # sprite key -> article keys (exact title first)
    for title in titles:
        k = norm(title)
        s = sprite_key_for_title(k, set(sprites))
        if s:
            sprite_of[k] = s
            candidates[s].insert(0, k) if s == k else candidates[s].append(k)
    nodes = defaultdict(dict)
    edges = defaultdict(lambda: {"sources": set()})
    for title in titles:
        key = norm(title)
        if key in sprite_of:
            text = page(title)
            if text:
                nodes[key]["name"] = title
                parse_digimon(key, text, nodes, edges)
    # A sprite belongs to the first candidate article that is really a Digimon page
    # (an exact-title page can be a disambiguation page, e.g. "Rapidmon").
    for s, ks in candidates.items():
        SPRITE_TO_ARTICLE[s] = next((k for k in ks if nodes.get(k, {}).get("levels")), ks[0])
    for t in DEVICE_PAGES:
        parse_device(t, nodes, edges)
    cards = parse_cards(sprites)

    # Korean names: Wikimon's {{KOR}} entry first, then the official Korean reference (digimon.net).
    official = {}
    for f in ("official_ko_child.json", "official_ko_levels.json"):
        p = CACHE / f
        if not p.exists():
            continue
        data = json.loads(p.read_text())
        rows = [(r[0], r[1]) for r in data] if isinstance(data, list) else [(n, d) for rows in data.values() for n, d in rows]
        for ko, d in rows:
            for k in (norm(d), norm(d.replace("-first", "")), norm(re.sub(r"-v$", "", d))):
                official.setdefault(k, ko)
    official.update({"greymon": "그레이몬", "metalgreymon": "메탈그레이몬", "weregarurumon": "워가루몬"})

    out_nodes = {}
    for key, n in nodes.items():
        if not n.get("levels") and not n.get("device_levels"):
            continue  # not a Digimon article (e.g. a device page linked from an evolution list)
        sp = dict(sprites.get(sprite_of.get(key, key), {}))
        for extra in n.get("extra_sprite_keys", ()):
            for kind, f in sprites.get(extra, {}).items():
                sp.setdefault(kind, f)
        if not n.get("ko"):
            n["ko"] = official.get(key, "")
        levels = sorted(n.get("levels", set()) | n.get("device_levels", set()),
                        key=lambda x: LEVEL_ORDER.index(x) if x in LEVEL_ORDER else 99)
        level = n.get("level") or next((lv for lv in LEVEL_ORDER if lv in n.get("device_levels", set())), "")
        out_nodes[key] = {"name": n.get("name", key), "ko": n.get("ko", ""), "level": level, "attribute": n.get("attribute") or next(iter(sorted(n.get("attributes", set()))), ""), "levels": levels,
                          "attributes": sorted(n.get("attributes", set())), "sprites": sp}
    out_edges = []
    for (a, b), e in sorted(edges.items()):
        if a == b or a not in out_nodes or b not in out_nodes:
            continue
        item = {"from": a, "to": b, "sources": sorted(e["sources"])}
        for k in ("canon", "jogress", "warp"):
            if e.get(k):
                item[k] = e[k]
        out_edges.append(item)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    meta = {
        "source": "Wikimon (https://wikimon.net) - text licensed CC BY-SA 3.0; sprites are not included",
        "fetched": (CACHE / "fetched_at.txt").read_text().strip() if (CACHE / "fetched_at.txt").exists() else "",
        "sprite_list": "Wikimon file names snapshot (tools/digimon/.cache/wikimon_images.json)",
        "edge_sources": "VB = Vital Bracelet (from Digimon pages), DMC/DPC = color V-Pet device pages or references",
    }
    OUT.write_text(json.dumps({"meta": meta, "nodes": out_nodes, "edges": out_edges, "cards": cards},
                              ensure_ascii=False, indent=1))
    print(f"nodes {len(out_nodes)}, edges {len(out_edges)}, cards {len(cards)} -> {OUT.relative_to(HERE.parent.parent)}")


if __name__ == "__main__":
    import sys
    sys.path.insert(0, str(HERE))
    main()
