# Northline Q3 2026 R&M

A take-home exercise for Northline Industrial Services, using synthetic data. The pipeline builds Q3 2026 repair and maintenance (R&M) cost in USD by branch and month from the raw ERP files, logs data quality issues, and reconciles the total to Accounting's reported figure to the cent.

**Start with [REPORT.md](REPORT.md).**

## How to run

Requires Python 3.11 or later. From the repository root:

```
uv run run.py
```

Without uv: `pip install -r requirements.txt`, then `python run.py`.

`run.py` writes its outputs to `output/` and exits with code 1 if any check fails. The first run downloads DuckDB's Excel extension, so it needs internet access.

Optional analyses: `uv run analysis/scenarios.py` (bridge search and decision sensitivity) and `uv run profiling/run_profiling.py` (profiling queries).

## Repository map

- `analysis/`: bridge search and decision sensitivity, with results in `analysis/results/`.
- `config/`: Finance rules (`rules.toml`) and pipeline settings (`pipeline.toml`).
- `data/raw/`: the raw data pack and its README with the Finance rules. Read-only.
- `docs/`: decisions, bridge, sensitivity, design memo, AI use and the AI log.
- `output/`: pipeline outputs, including the graded `rm_q3_by_branch.csv`.
- `profiling/`: profiling queries, results and findings.
- `sql/`: pipeline SQL, one step per file, run in order by `run.py`.
- `verify/`: an independent rebuild by a second model, and its comparison.

## Where the Finance rules live

**[config/rules.toml](config/rules.toml), owned by Finance,** holds the Finance rules from [data/raw/README.md](data/raw/README.md) and every confirmed treatment decision. Each value cites its source; the reasoning is in [docs/decisions.md](docs/decisions.md).

**[config/pipeline.toml](config/pipeline.toml), owned by Data Engineering,** holds paths, outputs and other settings. No rule value is hardcoded in SQL or Python.
