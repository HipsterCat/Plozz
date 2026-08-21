#!/usr/bin/env python3
"""Builds the offline kino.pub demo catalogue bundled with ProviderKinoPubDemo.

Reads two local databases from the kinopub-apple-client checkout — the kino.pub
item snapshot and the metadata record — and writes one JSON file. Nothing here
runs at app runtime; regenerate only when the demo set should change.

    python3 tools/kinopub-demo/build_catalog.py \
        --record ../kinopub-apple-client/tools/metadata-ingest/data/record.db \
        --out Sources/ProviderKinoPubDemo/Resources/KinoPubDemoCatalog.json
"""
import argparse
import json
import sqlite3
from collections import defaultdict

# kino.pub item types → the provider-agnostic kinds Plozz understands.
KIND = {
    "movie": "movie", "3d": "movie", "documovie": "movie", "concert": "movie",
    "serial": "series", "docuserial": "series", "tvshow": "series",
}

POSTER = "https://m.staticpop.net/poster/item/{size}/{id}.jpg"


def sized(url, spec):
    """Yandex avatar URLs end in a size token; `orig` is a 3 MB backdrop nobody
    on a TV needs. Swapping the token for a concrete size cuts it ~15x."""
    if not url:
        return None
    return url.rsplit("/", 1)[0] + "/" + spec if url.endswith("/orig") else url


def rows(db):
    q = """
    SELECT kp.value          AS kinopub_id,
           rp.body           AS kinopoisk,
           t.id              AS title_id,
           t.title_ru, t.title_original, t.year
    FROM title t
    JOIN title_external_id kp ON kp.title_id = t.id AND kp.namespace = 'kinopub'
    JOIN title_external_id ki ON ki.title_id = t.id AND ki.namespace = 'kinopoisk'
    JOIN raw_payload rp ON rp.source = 'kinopoisk'
                       AND rp.kind = 'film'
                       AND rp.source_key = ki.value
    """
    return db.execute(q).fetchall()


def load_side_tables(db, title_ids):
    marks = ",".join("?" * len(title_ids))
    genres = defaultdict(list)
    for tid, name in db.execute(
        f"SELECT title_id, name FROM genre WHERE source='kinopoisk' AND title_id IN ({marks})",
        title_ids,
    ):
        genres[tid].append(name)

    cast = defaultdict(list)
    for tid, name_ru, name_en, photo, dept, character, ordinal in db.execute(
        f"""SELECT c.title_id, p.name_ru, p.name_en, p.photo, c.department, c.character, c.ord
            FROM title_credit c JOIN person p ON p.id = c.person_id
            WHERE c.title_id IN ({marks})
            ORDER BY c.title_id, c.ord""",
        title_ids,
    ):
        cast[tid].append({
            "name": name_ru or name_en or "",
            "role": character or None,
            "kind": (dept or "actor").capitalize(),
            "imageURL": sized(photo, "200x200") or None,
            "ord": ordinal if ordinal is not None else 999,
        })
    return genres, cast


def build(record_db, limit):
    db = sqlite3.connect(record_db)
    raw = rows(db)

    picked = []
    for kinopub_id, body, title_id, title_ru, title_original, year in raw:
        kp = json.loads(body)
        # The demo only wants titles that can fill a hero: description, a 16:9
        # cover and a logo. Everything else would show as an empty slab.
        if not (kp.get("description") and kp.get("cover_url") and kp.get("logo_url")):
            continue
        rating = kp.get("rating_kinopoisk") or 0
        votes = kp.get("rating_kinopoisk_vote_count") or 0
        if rating < 6.5 or votes < 5000:
            continue
        picked.append((kinopub_id, kp, title_id, title_ru, title_original, year, rating, votes))

    picked.sort(key=lambda r: r[7], reverse=True)
    seen_ids = set()
    deduped = []
    for row in picked:
        if row[0] in seen_ids:
            continue
        seen_ids.add(row[0])
        deduped.append(row)
    picked = deduped[:limit]

    title_ids = [p[2] for p in picked]
    genres, cast = load_side_tables(db, title_ids)

    items = []
    for kinopub_id, kp, title_id, title_ru, title_original, year, rating, votes in picked:
        is_serial = bool(kp.get("serial"))
        kind = "series" if is_serial else "movie"
        # Copy: the same title can back more than one demo row, and popping
        # the sort key in place would empty it for the second reader.
        people = [
            {k: v for k, v in person.items() if k != "ord"}
            for person in sorted(cast.get(title_id, []), key=lambda p: p["ord"])[:18]
        ]

        items.append({
            "id": str(kinopub_id),
            "kind": kind,
            "title": title_ru or kp.get("name_ru") or title_original or "",
            "originalTitle": title_original or kp.get("name_original") or None,
            "year": year or kp.get("year"),
            "overview": kp.get("description"),
            "tagline": kp.get("slogan") or None,
            "genres": genres.get(title_id, [])[:4],
            "runtimeMinutes": kp.get("film_length"),
            "officialRating": kp.get("rating_age_limits"),
            "imdbRating": kp.get("rating_imdb"),
            "kinopoiskRating": rating,
            "posterURL": POSTER.format(size="medium", id=kinopub_id),
            "posterWideURL": POSTER.format(size="wide", id=kinopub_id),
            "backdropURL": sized(kp.get("cover_url"), "1920x1080"),
            "logoURL": sized(kp.get("logo_url"), "320x320"),
            "people": people,
            "seasonCount": 3 if is_serial else None,
        })

    return {"schema": 1, "items": items}


def rowsets(catalog):
    """Splits the catalogue into the shelves Home renders."""
    items = catalog["items"]
    by_id = {i["id"]: i for i in items}

    def ids(pred, limit=20):
        return [i["id"] for i in items if pred(i)][:limit]

    series = ids(lambda i: i["kind"] == "series")
    movies = ids(lambda i: i["kind"] == "movie")

    genre_rows = []
    seen = defaultdict(list)
    for i in items:
        for g in i["genres"]:
            seen[g].append(i["id"])
    for genre, members in sorted(seen.items(), key=lambda kv: -len(kv[1]))[:5]:
        if len(members) >= 8:
            genre_rows.append({"id": f"genre-{genre}", "title": genre, "itemIDs": members[:20]})

    rows = [
        {"id": "continue", "title": "Продолжить просмотр", "itemIDs": [i["id"] for i in items[:6]]},
        {"id": "latest", "title": "Новинки", "itemIDs": [i["id"] for i in items[:20]]},
        {"id": "series", "title": "Сериалы", "itemIDs": series},
        {"id": "movies", "title": "Фильмы", "itemIDs": movies},
    ] + genre_rows

    catalog["rows"] = [r for r in rows if len(r["itemIDs"]) >= 4]
    # Deterministic, plausible resume positions for the Continue Watching row.
    resume = {}
    for n, item_id in enumerate(catalog["rows"][0]["itemIDs"]):
        runtime = by_id[item_id].get("runtimeMinutes") or 100
        resume[item_id] = round(runtime * 60 * (0.12 + 0.13 * n), 0)
    catalog["resume"] = resume
    return catalog


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--record", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=140)
    a = ap.parse_args()

    cat = rowsets(build(a.record, a.limit))
    with open(a.out, "w", encoding="utf-8") as fh:
        json.dump(cat, fh, ensure_ascii=False, indent=1)
    print(f"{len(cat['items'])} items, {len(cat['rows'])} rows → {a.out}")
