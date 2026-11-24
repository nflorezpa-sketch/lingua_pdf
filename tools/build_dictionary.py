"""Genera el diccionario offline inglés→español de LinguaPDF.

Fuente: extracción de Wiktionary en inglés hecha por wiktextract (kaikki.org).
Licencia de los datos: CC BY-SA 4.0 / GFDL (ver assets/dict/LICENSE.txt).

Uso:
    python -I tools/build_dictionary.py <kaikki-English.jsonl.gz> assets/dict/en_es.db
"""
import gzip
import json
import os
import sqlite3
import sys
from collections import OrderedDict

TARGET = "es"
MAX_SENSES = 8
MAX_WORDS_PER_SENSE = 6
POS_ES = {
    "noun": "sustantivo", "verb": "verbo", "adj": "adjetivo", "adv": "adverbio",
    "prep": "preposición", "pron": "pronombre", "conj": "conjunción", "intj": "interjección",
    "det": "determinante", "article": "artículo", "num": "numeral", "phrase": "expresión",
    "prep_phrase": "expresión", "name": "nombre propio", "particle": "partícula",
    "contraction": "contracción", "abbrev": "abreviatura", "proverb": "refrán",
}
SKIP_FORM_TAGS = {"table-tags", "inflection-template", "class", "romanization", "obsolete", "archaic"}


def es_translations(entry):
    """[(sense, [palabras])] en orden, de nivel de entrada y de cada acepción."""
    items = list(entry.get("translations") or [])
    for s in entry.get("senses") or []:
        items.extend(s.get("translations") or [])
    groups = OrderedDict()
    for t in items:
        if (t.get("lang_code") or t.get("code")) != TARGET:
            continue
        w = (t.get("word") or "").strip()
        if not w or len(w) > 60:
            continue
        sense = (t.get("sense") or "").strip()
        lst = groups.setdefault(sense, [])
        if w not in lst and len(lst) < MAX_WORDS_PER_SENSE:
            lst.append(w)
    return list(groups.items())[:MAX_SENSES]


def ipa_of(entry):
    us = uk = other = None
    for s in entry.get("sounds") or []:
        ipa = s.get("ipa")
        if not ipa:
            continue
        tags = set(s.get("tags") or [])
        if "US" in tags or "General-American" in tags:
            us = us or ipa
        elif "UK" in tags or "Received-Pronunciation" in tags:
            uk = uk or ipa
        else:
            other = other or ipa
    return us or uk or other


def form_links(entry):
    """Formas flexionadas que apuntan a esta palabra: (forma, descripción)."""
    out = []
    for f in entry.get("forms") or []:
        form = (f.get("form") or "").strip()
        tags = set(f.get("tags") or [])
        if not form or tags & SKIP_FORM_TAGS or form == entry.get("word"):
            continue
        out.append((form, ", ".join(sorted(tags))))
    return out


def main(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst):
        os.remove(dst)
    db = sqlite3.connect(dst)
    db.executescript(
        """
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
        CREATE TABLE entries(id INTEGER PRIMARY KEY, key TEXT NOT NULL, word TEXT NOT NULL,
                             pos TEXT, ipa TEXT);
        CREATE TABLE senses(entry_id INTEGER NOT NULL, idx INTEGER NOT NULL, gloss TEXT,
                            es TEXT NOT NULL);
        CREATE TABLE forms(key TEXT NOT NULL, lemma TEXT NOT NULL, info TEXT);
        """
    )
    form_rows = []   # (forma, lema, info) — se filtran al final
    lemma_keys = set()
    n = kept = 0
    with gzip.open(src, "rt", encoding="utf-8") as fh:
        for line in fh:
            n += 1
            if n % 200000 == 0:
                print(f"  {n:,} entradas leídas, {kept:,} guardadas", flush=True)
            e = json.loads(line)
            if e.get("lang_code") != "en":
                continue
            word = e.get("word") or ""
            pos = e.get("pos") or ""
            # Formas que remiten a un lema ("picking" -> "present participle of pick").
            for s in e.get("senses") or []:
                for fo in s.get("form_of") or []:
                    lemma = (fo.get("word") or "").strip()
                    if lemma and lemma != word:
                        gloss = (s.get("glosses") or [""])[0]
                        form_rows.append((word.lower(), lemma, gloss[:120]))
            trs = es_translations(e)
            if not trs:
                continue
            kept += 1
            cur = db.execute(
                "INSERT INTO entries(key, word, pos, ipa) VALUES (?,?,?,?)",
                (word.lower(), word, POS_ES.get(pos, pos), ipa_of(e)),
            )
            eid = cur.lastrowid
            lemma_keys.add(word.lower())
            for i, (sense, words) in enumerate(trs):
                db.execute(
                    "INSERT INTO senses(entry_id, idx, gloss, es) VALUES (?,?,?,?)",
                    (eid, i, sense[:160] or None, ", ".join(words)),
                )
            for form, info in form_links(e):
                form_rows.append((form.lower(), word, info))

    seen = set()
    for key, lemma, info in form_rows:
        if lemma.lower() not in lemma_keys or key in lemma_keys and key == lemma.lower():
            continue
        k = (key, lemma.lower())
        if k in seen:
            continue
        seen.add(k)
        db.execute("INSERT INTO forms(key, lemma, info) VALUES (?,?,?)", (key, lemma, info))

    db.executescript(
        """
        CREATE INDEX idx_entries_key ON entries(key);
        CREATE INDEX idx_senses_entry ON senses(entry_id, idx);
        CREATE INDEX idx_forms_key ON forms(key);
        """
    )
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"Listo: {kept:,} entradas con traducción al español, {len(seen):,} formas. "
          f"Tamaño: {os.path.getsize(dst) / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
