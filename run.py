# /// script
# requires-python = ">=3.11"
# dependencies = ["duckdb==1.5.6"]
# ///
"""Northline Q3 2026 R&M build.

Thin runner. It loads config/rules.toml (Finance rules, owned by Finance) and
config/pipeline.toml (paths and settings, owned by Data Engineering) into an
in-memory DuckDB, executes sql/NN_*.sql in order, writes the output tables
named in [outputs], and fails (exit 1) if any row of the `checks` table is
false. All logic lives in sql/ and every rule value in config/rules.toml.

Usage (from anywhere):  uv run run.py
"""

import os
import sys
import tomllib
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
CONFIG_FILES = [ROOT / "config" / "rules.toml", ROOT / "config" / "pipeline.toml"]
SQL_DIR = ROOT / "sql"


def merge_config(into: dict, other: dict, path: str = "") -> dict:
    """Merge config files section by section; a key defined in both is an error."""
    for key, value in other.items():
        name = f"{path}.{key}" if path else key
        if isinstance(value, dict) and isinstance(into.get(key), dict):
            merge_config(into[key], value, name)
        elif key in into:
            raise ValueError(f"config key '{name}' is defined in more than one config file")
        else:
            into[key] = value
    return into


def load_config(con: duckdb.DuckDBPyConnection, node: dict, prefix: str = "") -> None:
    """A value or list of values -> variable <prefix>_<key>; a list of tables -> table cfg_<prefix>_<key>."""
    for key, value in node.items():
        name = f"{prefix}_{key}" if prefix else key
        if isinstance(value, dict):
            load_config(con, value, name)
        elif isinstance(value, list) and value and isinstance(value[0], dict):
            con.execute(f"CREATE TABLE cfg_{name} AS SELECT UNNEST(?, recursive := true)", [value])
        else:
            con.execute(f"SET VARIABLE {name} = ?", [value])


def write_output(con: duckdb.DuckDBPyConnection, table: str, path: Path) -> None:
    """Write a table to CSV, then read it back and require an exact match."""
    path.parent.mkdir(parents=True, exist_ok=True)
    con.execute(f"COPY (SELECT * FROM {table}) TO '{path.as_posix()}' (HEADER)")
    header = path.read_text(encoding="utf-8").splitlines()[0]
    if header != ",".join(con.table(table).columns):
        raise RuntimeError(f"{path}: header {header!r} does not match table {table}")
    mismatches = con.execute(
        f"""
        WITH written AS (SELECT * FROM read_csv('{path.as_posix()}', header = true, all_varchar = true)),
             expected AS (SELECT COLUMNS(*)::VARCHAR FROM {table})
        SELECT (SELECT count(*) FROM (FROM written EXCEPT ALL FROM expected))
             + (SELECT count(*) FROM (FROM expected EXCEPT ALL FROM written))
        """
    ).fetchone()[0]
    if mismatches:
        raise RuntimeError(f"{path}: {mismatches} rows differ from table {table} after writing")


def main() -> int:
    os.chdir(ROOT)  # config and SQL use repo-relative paths
    config: dict = {}
    for config_file in CONFIG_FILES:
        merge_config(config, tomllib.loads(config_file.read_text(encoding="utf-8")))
    outputs = {table: Path(path) for table, path in config["outputs"].items()}
    for path in outputs.values():
        path.unlink(missing_ok=True)  # never leave a stale deliverable behind

    con = duckdb.connect()
    load_config(con, config)
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        print(f"run  {sql_file.relative_to(ROOT).as_posix()}")
        con.execute(sql_file.read_text(encoding="utf-8"))

    checks = con.execute("SELECT check_id, description, passed, detail FROM checks ORDER BY check_id").fetchall()
    failed = [c for c in checks if not c[2]]
    write_output(con, "checks", outputs.pop("checks"))
    for check_id, description, passed, detail in checks:
        print(f"{'ok  ' if passed else 'FAIL'} {check_id} {description} ({detail})")
    if failed:
        print(f"\nBUILD FAILED: {len(failed)} of {len(checks)} checks false. Only {config['outputs']['checks']} was written.")
        return 1

    for table, path in outputs.items():
        write_output(con, table, path)
        print(f"wrote {path.as_posix()}")
    print(f"\nBUILD OK: {len(checks)} checks passed.\n")
    for row in con.execute("SELECT * FROM rm_q3_by_branch").fetchall():
        print("  ".join(f"{value:>12}" for value in row))
    return 0


if __name__ == "__main__":
    sys.exit(main())
