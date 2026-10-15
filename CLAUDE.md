# CLAUDE.md — Northline Q3 R&M Exercise

## What this repo is
A take-home exercise. Build Q3 2026 repair & maintenance (R&M) cost in USD by branch and month from raw ERP files, log data quality issues, and reconcile to Accounting's reported total to the cent.

- **Spec:** `data/raw/README.md` (Finance rules) and `docs/exercise.pdf` (task). The spec wins. If the data conflicts with it or is ambiguous, **stop and ask**. Don't improvise a rule.
- **Rule values:** `config/rules.toml` is the single source of truth. Never hardcode rule values (accounts, operations, dates, FX type, dedupe keys) in SQL or Python; read them from config.

## How we work
- **Stage-gated.** Do only the stage you are asked to do, then stop and report. Stages: profile → (human decides treatments) → build → verify → bridge → write-ups.
- **Profiling means no transforms.** Report what's in the data; the human decides what it means.
- **Every human decision goes in `docs/decisions.md`.** Propose wording and ask for confirmation before editing this file.
- **Log AI corrections in `docs/ai_log.md`.** When the human corrects something you did or proposed, append an entry using the template there. Never edit existing entries.

## Stack and conventions
- DuckDB, in-memory, reading raw files directly. No database file is required.
- Transformations live in numbered `.sql` files under `sql/`. `run.py` is a thin runner: it loads config, executes the SQL in order, and writes outputs.
- `run.py` declares its dependencies inline (PEP 723) so `uv run run.py` works. Keep `requirements.txt` in sync.
- Keep SQL readable over clever. It must be explainable and editable live by a human.
- `data/raw/` is read-only. Never modify, clean or overwrite raw files.

## Required checks (the build must fail if any are false)
- Row conservation: raw rows = kept rows + rows in each excluded bucket, per source.
- Every data quality rule reports affected rows and USD.
- `output/rm_q3_by_branch.csv` has exactly the columns Branch, Month, RM_USD, with Month as YYYY-MM and RM_USD to 2 decimals with no symbols.
- The bridge to Accounting's total has a residual of exactly 0.00. No plugs.

## Determinism
The pipeline makes no LLM calls. Same inputs, same outputs, to the cent.
