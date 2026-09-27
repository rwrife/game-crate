#!/usr/bin/env python3
"""Rebuild the committed v1 SQLite fixture from the frozen migration SQL.

Run from any directory: python3 Packages/CrateStore/Tools/regenerate_v1_fixture.py
Requires only Python's standard sqlite3 module. IDs, dates, and insert order are fixed.
"""
import pathlib
import re
import sqlite3
import tempfile
import os

PACKAGE = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PACKAGE / "Sources/CrateStore/CrateStore.swift"
OUTPUT = PACKAGE / "Tests/CrateStoreTests/Fixtures/v1.sqlite"
GAME = "00000000-0000-0000-0000-000000000001"
PERSON = "00000000-0000-0000-0000-000000000002"
PLAY = "00000000-0000-0000-0000-000000000003"


def main():
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(r'registerMigration\("v1"\).*?db\.execute\(sql: """(.*?)"""\)', source, re.S)
    if not match:
        raise SystemExit("frozen v1 SQL not found")
    fd, temporary = tempfile.mkstemp(prefix="v1-", suffix=".sqlite", dir=OUTPUT.parent)
    os.close(fd)
    try:
        connection = sqlite3.connect(temporary)
        connection.execute("PRAGMA page_size=4096")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.executescript(match.group(1))
        connection.execute("CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
        connection.execute("INSERT INTO grdb_migrations VALUES ('v1')")
        connection.execute(
            "INSERT INTO games VALUES (?,?,?,?,?,?,?,?)",
            (GAME, "Azul", None, None, None, '[{"rawValue":"family"}]', 100.0, "fixture game"),
        )
        connection.execute("INSERT INTO people VALUES (?,?,?,?)", (PERSON, "Ana", None, None))
        connection.execute(
            "INSERT INTO plays VALUES (?,?,?,?,?)", (PLAY, GAME, 200.0, "fixture play", None)
        )
        connection.execute(
            "INSERT INTO play_players VALUES (?,?,?,?)", (PLAY, PERSON, 4, "fixture rating")
        )
        connection.commit()
        connection.execute("VACUUM")
        connection.close()
        os.replace(temporary, OUTPUT)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(OUTPUT)


if __name__ == "__main__":
    main()
