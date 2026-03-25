#!/usr/bin/env python3
"""
build_formats_db.py

Generates the seed SQLite database (formats.db) for qw's hex editor.
Populates signatures, sections, and fields tables from what was previously
hardcoded in MagicBytes.swift, FileLayout.swift, and FileFormatInterpreter.swift.

Usage:
    python3 tools/build_formats_db.py
"""

import json
import os
import sqlite3
from datetime import date

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DB_PATH = os.path.join(PROJECT_ROOT, "qw", "qw", "Resources", "formats.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS signatures (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
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


def insert_signatures(conn):
    """Insert all 23 signatures from MagicBytes.swift registry + MP4."""
    sigs = [
        # (id, name, description, magic_bytes_hex, offset, priority)
        (1, "PNG Image", "Portable Network Graphics image",
         bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), 0, 10),
        (2, "JPEG Image", "JPEG/JFIF image",
         bytes([0xFF, 0xD8, 0xFF]), 0, 10),
        (3, "GIF Image", "Graphics Interchange Format image",
         bytes([0x47, 0x49, 0x46, 0x38]), 0, 10),
        (4, "PDF Document", "Portable Document Format",
         bytes([0x25, 0x50, 0x44, 0x46]), 0, 10),
        (5, "ZIP Archive", "ZIP compressed archive",
         bytes([0x50, 0x4B, 0x03, 0x04]), 0, 10),
        (6, "ZIP Archive (empty)", "ZIP archive (empty archive)",
         bytes([0x50, 0x4B, 0x05, 0x06]), 0, 9),
        (7, "Gzip", "Gzip compressed data",
         bytes([0x1F, 0x8B]), 0, 10),
        (8, "Bzip2", "Bzip2 compressed data",
         bytes([0x42, 0x5A, 0x68]), 0, 10),
        (9, "XZ", "XZ compressed data",
         bytes([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]), 0, 10),
        (10, "Mach-O Universal Binary", "Mach-O universal (fat) binary",
         bytes([0xCA, 0xFE, 0xBA, 0xBE]), 0, 10),
        (11, "Mach-O (32-bit)", "Mach-O 32-bit executable",
         bytes([0xFE, 0xED, 0xFA, 0xCE]), 0, 10),
        (12, "Mach-O (64-bit)", "Mach-O 64-bit executable",
         bytes([0xFE, 0xED, 0xFA, 0xCF]), 0, 10),
        (13, "Mach-O (64-bit, reversed)", "Mach-O 64-bit executable (little-endian)",
         bytes([0xCF, 0xFA, 0xED, 0xFE]), 0, 10),
        (14, "Mach-O (32-bit, reversed)", "Mach-O 32-bit executable (little-endian)",
         bytes([0xCE, 0xFA, 0xED, 0xFE]), 0, 10),
        (15, "ELF Executable", "Executable and Linkable Format",
         bytes([0x7F, 0x45, 0x4C, 0x46]), 0, 10),
        (16, "Windows PE/EXE", "Windows Portable Executable",
         bytes([0x4D, 0x5A]), 0, 8),
        (17, "RIFF (WAV/AVI)", "Resource Interchange File Format container",
         bytes([0x52, 0x49, 0x46, 0x46]), 0, 10),
        (18, "WebAssembly Binary", "WebAssembly binary module",
         bytes([0x00, 0x61, 0x73, 0x6D]), 0, 10),
        (19, "SQLite", "SQLite database file",
         bytes([0x53, 0x51, 0x4C, 0x69, 0x74, 0x65]), 0, 10),
        (20, "XML", "XML document",
         bytes([0x3C, 0x3F, 0x78, 0x6D, 0x6C]), 0, 2),
        (21, "JSON (heuristic)", "Likely JSON document",
         bytes([0x7B]), 0, 1),
        (22, "MP4 Video", "MPEG-4 Part 14 video container",
         bytes([0x66, 0x74, 0x79, 0x70]), 4, 10),  # "ftyp" at offset 4
    ]
    for s in sigs:
        conn.execute(
            "INSERT INTO signatures (id, name, description, magic_bytes, magic_offset, magic_mask, priority) "
            "VALUES (?, ?, ?, ?, ?, NULL, ?)",
            (s[0], s[1], s[2], s[3], s[4], s[5]),
        )


def insert_sections(conn):
    """Insert static section definitions for PNG, JPEG, PDF, ELF."""
    sections = [
        # PNG sections (signature_id=1)
        (1, "PNG Signature", "signature",
         "8-byte PNG file signature (\\x89PNG\\r\\n\\x1a\\n)",
         "0", "8", None),
        (1, "IHDR", "header",
         "Image header: width, height, bit depth, color type",
         "8", "25", None),  # 4+4+13+4 = 25 bytes

        # JPEG sections (signature_id=2)
        (2, "SOI", "signature",
         "Start of Image marker (FF D8)",
         "0", "2", None),

        # PDF sections (signature_id=4)
        (4, "PDF Header", "header",
         "PDF version header (e.g. %PDF-1.7)",
         "0", "9", None),

        # ELF sections (signature_id=15)
        (15, "ELF Header", "header",
         "ELF 64-bit header",
         "0", "64", None),
    ]
    for s in sections:
        conn.execute(
            "INSERT INTO sections (signature_id, name, kind, description, offset_expr, length_expr, color) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            s,
        )


def insert_fields(conn):
    """Insert field definitions for PNG IHDR, JPEG APP0, and ELF header."""
    # value_map helper
    def vmap(d):
        return json.dumps(d) if d else None

    fields = [
        # PNG fields (signature_id=1)
        (1, "PNG Signature", "PNG Signature", 0, 8, "magic", "big", "hex", None),
        (1, "IHDR", "IHDR Length", 8, 4, "uint32", "big", "decimal", None),
        (1, "IHDR", "IHDR Chunk Type", 12, 4, "ascii", "big", "string", None),
        (1, "IHDR", "Width", 16, 4, "uint32", "big", "decimal", None),
        (1, "IHDR", "Height", 20, 4, "uint32", "big", "decimal", None),
        (1, "IHDR", "Bit Depth", 24, 1, "uint8", "big", "decimal", None),
        (1, "IHDR", "Color Type", 25, 1, "uint8", "big", "decimal",
         vmap({"0": "Grayscale", "2": "RGB", "3": "Indexed",
                "4": "Grayscale+Alpha", "6": "RGBA"})),
        (1, "IHDR", "Compression", 26, 1, "uint8", "big", "decimal",
         vmap({"0": "Deflate"})),
        (1, "IHDR", "Filter", 27, 1, "uint8", "big", "decimal",
         vmap({"0": "Adaptive"})),
        (1, "IHDR", "Interlace", 28, 1, "uint8", "big", "decimal",
         vmap({"0": "None", "1": "Adam7"})),

        # JPEG fields (signature_id=2)
        (2, "SOI", "SOI Marker", 0, 2, "magic", "big", "hex", None),
        (2, "APP0", "APP0 Marker", 2, 2, "magic", "big", "hex", None),
        (2, "APP0", "APP0 Length", 4, 2, "uint16", "big", "decimal", None),
        (2, "APP0", "Identifier", 6, 5, "ascii", "big", "string", None),
        (2, "APP0", "Version Major", 11, 1, "uint8", "big", "decimal", None),
        (2, "APP0", "Version Minor", 12, 1, "uint8", "big", "decimal", None),
        (2, "APP0", "Density Units", 13, 1, "uint8", "big", "decimal",
         vmap({"0": "No units (aspect ratio)", "1": "Pixels/inch", "2": "Pixels/cm"})),
        (2, "APP0", "X Density", 14, 2, "uint16", "big", "decimal", None),
        (2, "APP0", "Y Density", 16, 2, "uint16", "big", "decimal", None),

        # ELF fields (signature_id=15)
        (15, "ELF Header", "ELF Magic", 0, 4, "magic", "big", "hex", None),
        (15, "ELF Header", "Class", 4, 1, "uint8", "big", "decimal",
         vmap({"1": "32-bit", "2": "64-bit"})),
        (15, "ELF Header", "Data Encoding", 5, 1, "uint8", "big", "decimal",
         vmap({"1": "Little-endian", "2": "Big-endian"})),
        (15, "ELF Header", "ELF Version", 6, 1, "uint8", "big", "decimal", None),
        (15, "ELF Header", "OS/ABI", 7, 1, "uint8", "big", "decimal",
         vmap({"0": "System V", "1": "HP-UX", "2": "NetBSD", "3": "Linux",
                "6": "Solaris", "9": "FreeBSD", "12": "OpenBSD"})),
        (15, "ELF Header", "ABI Version", 8, 1, "uint8", "big", "decimal", None),
        (15, "ELF Header", "Padding", 9, 7, "bytes", "big", "hex", None),
        (15, "ELF Header", "Type", 16, 2, "uint16", "little", "decimal",
         vmap({"0": "None", "1": "Relocatable", "2": "Executable",
                "3": "Shared object", "4": "Core"})),
        (15, "ELF Header", "Machine", 18, 2, "uint16", "little", "decimal",
         vmap({"3": "x86", "8": "MIPS", "20": "PowerPC", "40": "ARM",
                "62": "x86-64", "183": "AArch64", "243": "RISC-V"})),
    ]

    for f in fields:
        conn.execute(
            "INSERT INTO fields (signature_id, section_name, name, offset, size, type, endianness, display_format, value_map) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            f,
        )


def main():
    print(f"Building formats database at {DB_PATH}")
    conn = create_db()
    insert_metadata(conn)
    insert_signatures(conn)
    insert_sections(conn)
    insert_fields(conn)
    conn.commit()

    # Verify
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM signatures")
    sig_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM sections")
    sec_count = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM fields")
    field_count = cur.fetchone()[0]
    conn.close()

    print(f"Done: {sig_count} signatures, {sec_count} sections, {field_count} fields")


if __name__ == "__main__":
    main()
