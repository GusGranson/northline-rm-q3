# /// script
# requires-python = ">=3.11"
# dependencies = ["duckdb==1.5.6"]
# ///
"""Profiling runner (read-only).

Runs every profiling/sql/*.sql against data/raw/ in a fresh in-memory DuckDB
and saves each named query's result to
profiling/results/<sql file stem>/<NN>_<query name>.csv.

A SQL file is setup statements (verbatim loads, measurement views) followed by
named queries. Each named query starts with a line `-- name: <query_name>`
and holds exactly one SELECT.

Usage (from the repo root):  uv run profiling/run_profiling.py
"""

import csv
import os
import re
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "profiling" / "sql"
RESULTS_DIR = ROOT / "profiling" / "results"

# Profiling lenses, not Finance rules: they only say where to look (the Q3
# window from the README, how many days either side of it to inspect, and the
# README's last-export timestamp). The build stage reads rule values from
# config/rules.toml.
PARAMS = {
    "q_start": "DATE '2026-07-01'",
    "q_end": "DATE '2026-09-30'",
    "boundary_days": "3",
    "last_export_at": "TIMESTAMP '2026-09-30 18:00'",
}

NAME_MARKER = re.compile(r"^--\s*name:\s*(\w+)\s*$", re.MULTILINE)


def is_code(line: str) -> bool:
    return bool(line.strip()) and not line.strip().startswith("--")


def has_sql(text: str) -> bool:
    return any(is_code(line) for line in text.splitlines())


def query_body(text: str) -> str:
    """The query without trailing comment lines (section dividers) or its final ';'."""
    lines = text.strip().splitlines()
    while lines and not is_code(lines[-1]):
        lines.pop()
    return "\n".join(lines).rstrip().rstrip(";")


def run_file(sql_path: Path) -> None:
    con = duckdb.connect()
    con.execute("SET threads = 1")  # stable row order and float sums between runs
    for name, value in PARAMS.items():
        con.execute(f"SET VARIABLE {name} = {value}")

    parts = NAME_MARKER.split(sql_path.read_text(encoding="utf-8"))
    setup, queries = parts[0], list(zip(parts[1::2], parts[2::2]))
    if has_sql(setup):
        con.execute(setup)

    out_dir = RESULTS_DIR / sql_path.stem
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.csv"):
        stale.unlink()

    print(sql_path.relative_to(ROOT).as_posix())
    for i, (name, query) in enumerate(queries, start=1):
        out = out_dir / f"{i:02d}_{name}.csv"
        body = query_body(query)
        con.execute(f"COPY ({body}\n) TO '{out.as_posix()}' (HEADER)")
        with out.open(newline="", encoding="utf-8") as f:
            rows = sum(1 for _ in csv.reader(f)) - 1
        print(f"  {out.relative_to(ROOT).as_posix()}  ({rows} rows)")
    con.close()


def main() -> None:
    os.chdir(ROOT)  # SQL files use repo-relative paths (data/raw/...)
    for sql_path in sorted(SQL_DIR.glob("*.sql")):
        run_file(sql_path)


if __name__ == "__main__":
    main()
