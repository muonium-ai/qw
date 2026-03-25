#!/usr/bin/env python3
"""
build_formats_db.py

Generates the seed SQLite database (formats.db) for qw's hex editor.
Reads format definitions from tools/formats.toml and populates signatures,
sections, and fields tables.

Usage:
    python3 tools/build_formats_db.py

Ticket: T-000040 — moved definitions to formats.toml
"""

import json
import os
import sqlite3
import tomllib
from datetime import date

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DB_PATH = os.path.join(PROJECT_ROOT, "qw", "qw", "Resources", "formats.db")
TOML_PATH = os.path.join(SCRIPT_DIR, "formats.toml")

SCHEMA = """
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS signatures (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    magic_bytes BLOB NOT NULL,
    magic_offset INTEGER DEFAULT 0,
    magic_mask BLOB,
    priority INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sections (
    id INTEGER PRIMARY KEY,
    signature_id INTEGER REFERENCES signatures(id),
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    description TEXT,
    offset_expr TEXT NOT NULL,
    length_expr TEXT NOT NULL,
    color TEXT
);

CREATE TABLE IF NOT EXISTS fields (
    id INTEGER PRIMARY KEY,
    signature_id INTEGER REFERENCES signatures(id),
    section_name TEXT,
    name TEXT NOT NULL,
    offset INTEGER NOT NULL,
    size INTEGER NOT NULL,
    type TEXT NOT NULL,
    endianness TEXT DEFAULT 'big',
    display_format TEXT,
    value_map TEXT
);
"""


def load_toml():
    with open(TOML_PATH, "rb") as f:
        return tomllib.load(f)


def create_db():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)
    return conn


def insert_metadata(conn):
    today = date.today().isoformat()
    conn.execute("INSERT INTO metadata VALUES ('version', '1')")
    conn.execute("INSERT INTO metadata VALUES ('last_updated', ?)", (today,))
    conn.execute("INSERT INTO metadata VALUES ('source_url', '')")


def insert_formats(conn, formats):
    """Insert signatures, sections, and fields from parsed TOML data."""
    for fmt in formats:
        sig_id = fmt["id"]
        magic = bytes(fmt["magic_bytes"])
        category = fmt.get("category", "")

        conn.execute(
            "INSERT INTO signatures (id, name, description, category, magic_bytes, magic_offset, magic_mask, priority) "
            "VALUES (?, ?, ?, ?, ?, ?, NULL, ?)",
            (sig_id, fmt["name"], fmt.get("description", ""), category,
             magic, fmt.get("offset", 0), fmt.get("priority", 0)),
        )

        # Sections
        for sec in fmt.get("sections", []):
            conn.execute(
                "INSERT INTO sections (signature_id, name, kind, description, offset_expr, length_expr, color) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (sig_id, sec["name"], sec["kind"], sec.get("description", ""),
                 sec["offset_expr"], sec["length_expr"], sec.get("color")),
            )

        # Fields
        for fld in fmt.get("fields", []):
            value_map = json.dumps(fld["value_map"]) if fld.get("value_map") else None
            conn.execute(
                "INSERT INTO fields (signature_id, section_name, name, offset, size, type, endianness, display_format, value_map) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (sig_id, fld.get("section_name"), fld["name"], fld["offset"],
                 fld["size"], fld["type"], fld.get("endianness", "big"),
                 fld.get("display_format"), value_map),
            )


def main():
    print(f"Loading format definitions from {TOML_PATH}")
    data = load_toml()
    formats = data["format"]
    print(f"Found {len(formats)} format definitions")

    print(f"Building formats database at {DB_PATH}")
    conn = create_db()
    insert_metadata(conn)
    insert_formats(conn, formats)
    conn.commit()

    # Verify
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM signatures")
    sig_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM sections")
    sec_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM fields")
    field_count = cur.fetchone()[0]

    # Show category breakdown
    cur.execute("SELECT category, COUNT(*) FROM signatures GROUP BY category ORDER BY category")
    categories = cur.fetchall()
    conn.close()

    print(f"Done: {sig_count} signatures, {sec_count} sections, {field_count} fields")
    for cat, count in categories:
        print(f"  {cat or '(none)'}: {count}")


if __name__ == "__main__":
    main()
