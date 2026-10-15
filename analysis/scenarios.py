# /// script
# requires-python = ">=3.11"
# dependencies = ["duckdb==1.5.6"]
# ///
"""Bridge search and sensitivity analysis (read-only; writes analysis/results/).

Builds the pipeline tables in memory exactly as run.py does (same config, same
sql/ files; no outputs written), then:

  1. Engine check: the scenario engine, run with every base treatment, must
     reproduce output/rm_q3_by_branch.csv to the cent, or the script stops.
  2. Bridge search: every combination of plausible Accounting methods
     (each manual JE in or out, FX average or month-end per month plus three
     whole-quarter FX methods, 7335-RM-HYD excluded per the account map, and
     each data quality treatment not applied). Every combination that lands
     exactly on Accounting's total is kept, not just the first.
  3. Sensitivity: each decision D-01..D-12 rerun with its most plausible
     alternative treatment, with the change per branch-month.

The alternatives below are hypotheses about what someone else might have done.
They live here, not in config, because they are not rules.

Usage (from anywhere):  uv run analysis/scenarios.py
"""

import csv
import itertools
import os
import sys
import tomllib
from decimal import ROUND_HALF_EVEN, ROUND_HALF_UP, Decimal
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import duckdb  # noqa: E402

import run  # noqa: E402  (reuses the runner's config loader and SQL order)

RESULTS = ROOT / "analysis" / "results"
CENT = Decimal("0.01")


def half_up(x: Decimal) -> Decimal:
    return x.quantize(CENT, ROUND_HALF_UP)


def half_even_double(x: float) -> Decimal:
    return Decimal(x).quantize(CENT, ROUND_HALF_EVEN)


# ---------------------------------------------------------------------------
# Pipeline tables
# ---------------------------------------------------------------------------

def build_pipeline() -> duckdb.DuckDBPyConnection:
    os.chdir(ROOT)
    config: dict = {}
    for config_file in run.CONFIG_FILES:
        run.merge_config(config, tomllib.loads(config_file.read_text(encoding="utf-8")))
    con = duckdb.connect()
    con.execute("SET threads = 1")  # fixed summation order for the DOUBLE scenario (D-07)
    run.load_config(con, config)
    for sql_file in sorted(run.SQL_DIR.glob("*.sql")):
        con.execute(sql_file.read_text(encoding="utf-8"))
    return con


SCENARIO_BASE_SQL = r"""
-- One row per staged ERP-A line, with each alternative reading precomputed.
CREATE TABLE scen_a AS
SELECT
    l.source_row,
    l.ext_cost_usd,
    l.ext_cost_raw,
    l.qty,
    l.oper,
    l.cust_num,
    l.exported_at,
    l.copy_rank = 1                                                        AS keep_latest,
    row_number() OVER (PARTITION BY l.line_key ORDER BY l.exported_at, l.source_row) = 1 AS keep_earliest,
    row_number() OVER (PARTITION BY l.sro, l.line, l.oper, l.whse_raw, l.trans_date_raw, l.trans_type,
                                    l.acct_raw, l.item, l.qty, l.unit_cost_raw, l.ext_cost_raw, l.cust_num
                       ORDER BY l.source_row) = 1                          AS keep_raw_first,
    l.trans_date                                                           AS d_mmdd,
    CASE WHEN TRY_STRPTIME(l.trans_date_raw, getvariable('erp_a_date_formats')[1]) IS NULL
         THEN TRY_STRPTIME(l.trans_date_raw, '%d/%m/%Y')::DATE ELSE l.trans_date END AS d_ddmm,
    CASE WHEN TRY_STRPTIME(l.trans_date_raw, getvariable('erp_a_date_formats')[1]) IS NULL
         THEN coalesce(TRY_STRPTIME(l.trans_date_raw, '%d/%m/%Y')::DATE, l.trans_date)
         ELSE l.trans_date END                                             AS d_ddmm_fallback,
    CASE WHEN TRY_STRPTIME(l.trans_date_raw, getvariable('erp_a_date_formats')[1]) IS NULL
         THEN NULL ELSE l.trans_date END                                   AS d_slash_dropped,
    list_contains(getvariable('rm_group_accounts'), l.acct)                AS acct_parsed_rm,
    list_contains(list_transform(getvariable('rm_group_accounts'), x -> x::VARCHAR), trim(l.acct_raw)) AS acct_trim_text_rm,
    list_contains(list_transform(getvariable('rm_group_accounts'), x -> x::VARCHAR), l.acct_raw)       AS acct_exact_text_rm,
    l.branch                                                               AS br_map,
    CASE WHEN list_contains(getvariable('branches_codes'), left(upper(trim(l.whse_raw)), 3))
         THEN left(upper(trim(l.whse_raw)), 3) END                        AS br_prefix,
    CASE WHEN list_contains(getvariable('branches_codes'), upper(trim(l.whse_raw)))
         THEN upper(trim(l.whse_raw)) END                                 AS br_trim_upper,
    CASE WHEN list_contains(getvariable('branches_codes'), l.whse_raw) THEN l.whse_raw END AS br_exact
FROM erp_a_lines AS l;

-- One row per ERP-B sheet row (journal lines and SUBTOTAL rows).
CREATE TABLE scen_b AS
SELECT
    b.row_type,
    b.amount_cad,
    TRY_CAST(b.amount_raw AS DECIMAL(18, 2))                                         AS amount_strict,
    TRY_CAST(replace(b.amount_raw, getvariable('erp_b_thousands_separator'), '') AS DOUBLE) AS amount_double,
    TRY_CAST(b.amount_raw AS DOUBLE)                                                 AS amount_double_strict,
    b.posting_date                                                                   AS d_ddmm,
    coalesce(TRY_STRPTIME(b.posting_date_raw, '%m/%d/%Y')::DATE, b.posting_date)     AS d_mmdd,
    b.is_rm_local_account                                                            AS rm_pattern,
    coalesce(list_contains(getvariable('rm_group_accounts'), m.group_account), false) AS rm_map
FROM erp_b_lines AS b
LEFT JOIN stg_account_map AS m USING (local_account);

-- Both CAD->USD rates per month (the Finance rate and the other column).
CREATE TABLE fx_both AS
SELECT
    Month AS month,
    max(TRY_CAST(rate_raw AS DECIMAL(18, 8))) FILTER (WHERE rate_column = getvariable('fx_rate_column'))  AS avg_rate,
    max(TRY_CAST(rate_raw AS DECIMAL(18, 8))) FILTER (WHERE rate_column <> getvariable('fx_rate_column')) AS me_rate,
    count(*) AS rate_columns
FROM raw_fx
UNPIVOT (rate_raw FOR rate_column IN (COLUMNS(* EXCLUDE (Month))))
GROUP BY Month;

-- Manual JE register and Accounting's reported total.
CREATE TABLE je AS
SELECT
    JE_ID AS je_id,
    TRY_CAST(PostedAt AS TIMESTAMP)              AS posted_at,
    Entity AS entity, Branch AS branch, Account AS account,
    TRY_CAST(Amount AS DECIMAL(18, 2))           AS amount,
    Description AS description,
    list_contains(getvariable('rm_group_accounts'), TRY_CAST(Account AS INTEGER)) IS TRUE AS is_rm_group_account,
    regexp_matches(Account, getvariable('erp_b_rm_local_account_pattern'))        AS is_rm_local_account,
    TRY_CAST(Account AS INTEGER) IS NULL         AS is_local_account
FROM read_csv(getvariable('sources_je_register'), header = true, all_varchar = true);

CREATE TABLE accounting_close AS
SELECT * FROM read_csv(getvariable('sources_accounting_close'), header = true, all_varchar = true);
"""

A_ENGINE_SQL = """
WITH a AS (
    SELECT
        o.*, s.*,
        CASE o.o_dates WHEN 'mmdd' THEN s.d_mmdd WHEN 'ddmm' THEN s.d_ddmm WHEN 'ddmm_fallback' THEN s.d_ddmm_fallback
                       WHEN 'slash_dropped' THEN s.d_slash_dropped END                                  AS d,
        CASE o.o_whse WHEN 'map' THEN s.br_map WHEN 'prefix' THEN s.br_prefix
                      WHEN 'trim_upper' THEN s.br_trim_upper WHEN 'exact_code' THEN s.br_exact END        AS br
    FROM a_opts AS o CROSS JOIN scen_a AS s
),
k AS (
    SELECT * FROM a
    WHERE d IS NOT NULL AND br IS NOT NULL
      AND CASE o_dedupe WHEN 'latest' THEN keep_latest WHEN 'earliest' THEN keep_earliest
                        WHEN 'raw_row' THEN keep_raw_first WHEN 'none' THEN true END
      AND CASE o_period WHEN 'transdate' THEN d BETWEEN getvariable('period_start') AND getvariable('period_end')
                        WHEN 'transdate_and_cutoff' THEN d BETWEEN getvariable('period_start') AND getvariable('period_end')
                                                    AND exported_at <= getvariable('erp_a_last_export_cutoff')
                        WHEN 'exported' THEN exported_at BETWEEN getvariable('period_start') AND getvariable('erp_a_last_export_cutoff')
                        WHEN 'all_dates' THEN true END
      AND CASE o_acct WHEN 'parsed' THEN acct_parsed_rm WHEN 'trim_text' THEN acct_trim_text_rm
                      WHEN 'exact_text' THEN acct_exact_text_rm END
      AND CASE o_capex WHEN 'excl_all' THEN NOT list_contains(getvariable('rm_capitalised_operations'), oper)
                       WHEN 'incl_all' THEN true
                       WHEN 'incl_first' THEN oper IS DISTINCT FROM getvariable('rm_capitalised_operations')[2]
                       WHEN 'incl_second' THEN oper IS DISTINCT FROM getvariable('rm_capitalised_operations')[1] END
      AND (o_reversals = 'incl' OR qty >= 0)
      AND (o_custnum = 'incl' OR cust_num IS NULL)
)
SELECT
    k.opt_id,
    coalesce(ra.to_branch, k.br)        AS branch,
    strftime(k.d, '%Y-%m')              AS month,
    sum(k.ext_cost_usd)                 AS usd,
    sum(TRY_CAST(k.ext_cost_raw AS DOUBLE)) AS usd_double
FROM k
LEFT JOIN cfg_branches_reassign AS ra ON ra.from_branch = k.br AND k.d >= ra.effective_from
GROUP BY ALL
ORDER BY ALL
"""

B_ENGINE_SQL = """
WITH b AS (
    SELECT
        o.*, s.*,
        CASE o.o_bdates WHEN 'ddmm' THEN s.d_ddmm ELSE s.d_mmdd END                          AS d,
        CASE o.o_text WHEN 'parsed' THEN s.amount_cad ELSE s.amount_strict END               AS amt,
        CASE o.o_text WHEN 'parsed' THEN s.amount_double ELSE s.amount_double_strict END     AS amt_double
    FROM b_opts AS o CROSS JOIN scen_b AS s
)
SELECT opt_id, strftime(d, '%Y-%m') AS month, sum(amt) AS cad, sum(amt_double) AS cad_double
FROM b
WHERE (row_type = 'journal' OR o_subtotal = 'incl')
  AND d BETWEEN getvariable('period_start') AND getvariable('period_end')
  AND CASE o_rm WHEN 'pattern' THEN rm_pattern WHEN 'map' THEN rm_map END
  AND amt IS NOT NULL
GROUP BY ALL
ORDER BY ALL
"""

A_DIMS = ["o_dedupe", "o_period", "o_dates", "o_acct", "o_whse", "o_capex", "o_reversals", "o_custnum"]
B_DIMS = ["o_rm", "o_text", "o_subtotal", "o_bdates"]
BASE_A = dict(o_dedupe="latest", o_period="transdate", o_dates="mmdd", o_acct="parsed", o_whse="map",
              o_capex="excl_all", o_reversals="incl", o_custnum="incl")
BASE_B = dict(o_rm="pattern", o_text="parsed", o_subtotal="excl", o_bdates="ddmm")


def run_engine(con, sql: str, table: str, dims: list[str], options: list[dict]) -> dict:
    """Run an engine over a list of option dicts; returns {opt_id: rows}."""
    con.execute(f"DROP TABLE IF EXISTS {table}")
    con.execute(f"CREATE TABLE {table} ({', '.join(['opt_id INTEGER'] + [f'{d} VARCHAR' for d in dims])})")
    con.executemany(f"INSERT INTO {table} VALUES ({', '.join(['?'] * (len(dims) + 1))})",
                    [[i] + [o[d] for d in dims] for i, o in enumerate(options)])
    out: dict = {i: [] for i in range(len(options))}
    for row in con.execute(sql).fetchall():
        out[row[0]].append(row[1:])
    return out


# ---------------------------------------------------------------------------
# FX methods: a month's CAD total -> USD, and the rate used for a CAD JE
# ---------------------------------------------------------------------------

def fx_methods(fx: dict, months: list[str]) -> dict:
    """name -> (translate(months_cad) -> {month: usd}, rate_for(month))."""
    methods = {}
    for choice in itertools.product(["avg", "me"], repeat=len(months)):
        rate = {m: fx[m][c] for m, c in zip(months, choice)}
        name = "per-month " + "/".join(f"{m[-2:]}:{c}" for m, c in zip(months, choice))
        methods[name] = (lambda cad, rate=rate: {m: half_up(v * rate[m]) for m, v in cad.items()},
                         lambda m, rate=rate: rate.get(m))
    last = months[-1]
    for label, key in [("Q3 total at last month's month-end rate", "me"), ("Q3 total at last month's average rate", "avg")]:
        r = fx[last][key]
        methods[label] = (lambda cad, r=r: {last: half_up(sum(cad.values(), Decimal(0)) * r)},
                          lambda m, r=r: r)
    mean_avg = sum((fx[m]["avg"] for m in months), Decimal(0)) / len(months)
    methods["each month at the quarter's mean average rate"] = (
        lambda cad: {m: half_up(v * mean_avg) for m, v in cad.items()}, lambda m: mean_avg)
    return methods


def main() -> int:
    RESULTS.mkdir(parents=True, exist_ok=True)
    con = build_pipeline()
    con.execute(SCENARIO_BASE_SQL)

    fx = {m: {"avg": a, "me": e} for m, a, e, n in con.execute("SELECT * FROM fx_both ORDER BY month").fetchall()}
    months = sorted(fx)
    fin_cells = {(b, m): v for b, m, v in con.execute("SELECT branch, month, rm_usd FROM rm_by_branch").fetchall()}
    fin_total = sum(fin_cells.values(), Decimal(0))
    acc_rows = con.execute("SELECT USD FROM accounting_close").fetchall()
    assert len(acc_rows) == 1, "expected one row in accounting_close_summary.csv"
    acc_total = Decimal(acc_rows[0][0])
    gap = acc_total - fin_total
    jes = con.execute("SELECT je_id, posted_at, entity, branch, account, amount, description, "
                      "is_rm_group_account, is_rm_local_account, is_local_account FROM je ORDER BY je_id").fetchall()
    methods = fx_methods(fx, months)
    base_fx = "per-month " + "/".join(f"{m[-2:]}:avg" for m in months)

    def je_usd(j, rate_for) -> Decimal | None:
        _, posted_at, _, _, _, amount, _, _, _, is_local = j
        if not is_local:
            return amount
        rate = rate_for(posted_at.strftime("%Y-%m"))
        return None if rate is None else half_up(amount * rate)

    # ---- 1. Engine check: base treatments reproduce the Part 1 output exactly
    a_base = run_engine(con, A_ENGINE_SQL, "a_opts", A_DIMS, [BASE_A])[0]
    b_base = run_engine(con, B_ENGINE_SQL, "b_opts", B_DIMS, [BASE_B])[0]
    cells = {(b, m): u for b, m, u, _ in a_base}
    lks = methods[base_fx][0]({m: c for m, c, _ in b_base})
    cells.update({(run_lks_branch(con), m): v for m, v in lks.items()})
    if cells != fin_cells:
        print("ENGINE CHECK FAILED: base scenario does not reproduce rm_by_branch")
        return 1
    print(f"engine check ok: base scenario reproduces all {len(cells)} branch-months, total {fin_total}")

    # ---- 2. Bridge search
    search_a = {
        "o_dedupe": ["latest", "none"],
        "o_period": ["transdate", "all_dates", "exported"],
        "o_dates": ["mmdd", "ddmm", "ddmm_fallback", "slash_dropped"],
        "o_acct": ["parsed", "trim_text", "exact_text"],
        "o_whse": ["map", "trim_upper", "exact_code"],
        "o_capex": ["excl_all", "incl_all", "incl_first", "incl_second"],
        "o_reversals": ["incl", "excl"],
        "o_custnum": ["incl", "excl"],
    }
    search_b = {"o_rm": ["pattern", "map"], "o_text": ["parsed", "dropped"],
                "o_subtotal": ["excl", "incl"], "o_bdates": ["ddmm", "mmdd"]}
    a_opts = [dict(zip(search_a, v)) for v in itertools.product(*search_a.values())]
    b_opts = [dict(zip(search_b, v)) for v in itertools.product(*search_b.values())]
    a_res = run_engine(con, A_ENGINE_SQL, "a_opts", A_DIMS, a_opts)
    b_res = run_engine(con, B_ENGINE_SQL, "b_opts", B_DIMS, b_opts)

    base_a_total = sum((u for _, _, u, _ in a_base), Decimal(0))
    a_delta: dict = {}
    for i, rows in a_res.items():
        a_delta.setdefault(sum((u for _, _, u, _ in rows), Decimal(0)) - base_a_total, []).append(i)
    base_lks_total = sum(lks.values(), Decimal(0))

    hits, evaluated = [], 0
    for bi, rows in b_res.items():
        cad = {m: c for m, c, _ in rows}
        for fx_name, (translate, rate_for) in methods.items():
            d_b = sum(translate(cad).values(), Decimal(0)) - base_lks_total
            je_vals = [je_usd(j, rate_for) for j in jes]
            for subset in itertools.product([False, True], repeat=len(jes)):
                if any(s and v is None for s, v in zip(subset, je_vals)):
                    continue
                d_j = sum((v for s, v in zip(subset, je_vals) if s), Decimal(0))
                evaluated += len(a_opts)
                for ai in a_delta.get(gap - d_b - d_j, []):
                    hits.append((a_opts[ai], b_opts[bi], fx_name, [j[0] for s, j in zip(subset, jes) if s], d_b, d_j))

    def deviations(a, b, fx_name, je_ids):
        out = [f"{k[2:]}={v}" for k, v in a.items() if v != BASE_A[k]]
        out += [f"{k[2:]}={v}" for k, v in b.items() if v != BASE_B[k]]
        if fx_name != base_fx:
            out.append(f"fx={fx_name}")
        out += [f"include {j}" for j in je_ids]
        return out

    with open(RESULTS / "bridge_closing_combinations.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["combination", "deviations_from_finance", "deviation_count", "erp_a_effect_usd", "lakeshore_effect_usd", "je_effect_usd"])
        ranked = sorted(hits, key=lambda h: (len(deviations(h[0], h[1], h[2], h[3])), deviations(h[0], h[1], h[2], h[3])))
        for n, (a, b, fx_name, je_ids, d_b, d_j) in enumerate(ranked, start=1):
            dev = deviations(a, b, fx_name, je_ids)
            w.writerow([n, "; ".join(dev), len(dev), gap - d_b - d_j, d_b, d_j])
    print(f"bridge search: gap {gap}; {evaluated:,} combinations evaluated; {len(hits)} close exactly")

    # Nearest non-closing combinations: how far the runners-up are from the gap
    import bisect
    a_keys = sorted(a_delta)
    near = []
    for bi, rows in b_res.items():
        cad = {m: c for m, c, _ in rows}
        for fx_name, (translate, rate_for) in methods.items():
            d_b = sum(translate(cad).values(), Decimal(0)) - base_lks_total
            je_vals = [je_usd(j, rate_for) for j in jes]
            for subset in itertools.product([False, True], repeat=len(jes)):
                if any(s and v is None for s, v in zip(subset, je_vals)):
                    continue
                d_j = sum((v for s, v in zip(subset, je_vals) if s), Decimal(0))
                need = gap - d_b - d_j
                pos = bisect.bisect_left(a_keys, need)
                for k in a_keys[max(pos - 1, 0):pos + 2]:
                    if k != need:
                        near.append((abs(need - k), k - need, a_delta[k][0], bi, fx_name,
                                     [j[0] for s, j in zip(subset, jes) if s]))
    near.sort(key=lambda x: x[0])
    with open(RESULTS / "bridge_nearest_misses.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["rank", "deviations_from_finance", "miss_usd"])
        for n, (_, miss, ai, bi, fx_name, je_ids) in enumerate(near[:10], start=1):
            w.writerow([n, "; ".join(deviations(a_opts[ai], b_opts[bi], fx_name, je_ids)), miss])

    # Single-item effects: each candidate alone, everything else at Finance's treatment
    singles = []
    for dim, values in search_a.items():
        for v in values[1:]:
            i = a_opts.index({**BASE_A, dim: v})
            singles.append((f"ERP-A {dim[2:]}={v}", sum((u for _, _, u, _ in a_res[i]), Decimal(0)) - base_a_total))
    for dim, values in search_b.items():
        for v in values[1:]:
            i = b_opts.index({**BASE_B, dim: v})
            cad = {m: c for m, c, _ in b_res[i]}
            singles.append((f"Lakeshore {dim[2:]}={v}", sum(methods[base_fx][0](cad).values(), Decimal(0)) - base_lks_total))
    base_cad = {m: c for m, c, _ in b_base}
    for name, (translate, _) in methods.items():
        if name != base_fx:
            singles.append((f"FX {name}", sum(translate(base_cad).values(), Decimal(0)) - base_lks_total))
    for j in jes:
        v = je_usd(j, methods[base_fx][1])
        singles.append((f"include {j[0]} ({j[3]} {j[4]}, posted {j[1]:%Y-%m-%d %H:%M})",
                        v if v is not None else "no rate for posting month"))
    with open(RESULTS / "bridge_single_effects.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["candidate", "effect_on_finance_total_usd"])
        w.writerows(singles)

    # ---- 3. Sensitivity: each decision with its most plausible alternative
    period_end = con.execute("SELECT getvariable('period_end')").fetchone()[0]
    closed_months = [(b, m) for b, m in con.execute(
        "SELECT r.from_branch, f.month FROM cfg_branches_reassign AS r, fx_both AS f "
        "WHERE f.month >= strftime(r.effective_from, '%Y-%m') ORDER BY 1, 2").fetchall()]
    scenarios = sensitivity_scenarios(jes, period_end, closed_months)
    a_opts_s = [{**BASE_A, **s.get("a", {})} for s in scenarios]
    b_opts_s = [{**BASE_B, **s.get("b", {})} for s in scenarios]
    a_s = run_engine(con, A_ENGINE_SQL, "a_opts", A_DIMS, a_opts_s)
    b_s = run_engine(con, B_ENGINE_SQL, "b_opts", B_DIMS, b_opts_s)
    lks_branch = run_lks_branch(con)
    summary, cell_rows = [], []
    for i, s in enumerate(scenarios):
        double = s.get("double", False)
        cells_s = {(b, m): (half_even_double(ud) if double else u) for b, m, u, ud in a_s[i]}
        for m, c, cd in b_s[i]:
            cells_s[(lks_branch, m)] = (half_even_double(cd * float(fx[m]["avg"])) if double
                                        else half_up(c * fx[m]["avg"]))
        for j in jes:
            if j[0] in s.get("jes", []):
                # a JE counts in its posting month, or in the quarter's last month when the
                # alternative treats the whole close register as Q3 activity
                month = months[-1] if s.get("je_month") == "register" else j[1].strftime("%Y-%m")
                key = (j[3], month)
                cells_s[key] = cells_s.get(key, Decimal(0)) + je_usd(j, methods[base_fx][1])
        for key in s.get("zero_rows", []):
            cells_s.setdefault(key, Decimal("0.00"))
        moved = []
        for key in sorted(set(cells_s) | set(fin_cells), key=lambda k: (k[0], k[1])):
            diff = cells_s.get(key, Decimal(0)) - fin_cells.get(key, Decimal(0))
            if diff != 0:
                moved.append((key, diff))
                cell_rows.append([s["decision"], s["primary"], s["alternative"], key[0], key[1],
                                  fin_cells.get(key, ""), cells_s.get(key, ""), diff])
        total_diff = sum(cells_s.values(), Decimal(0)) - fin_total
        summary.append([s["decision"], s["primary"], s["alternative"], total_diff,
                        f"{(total_diff / fin_total * 100):.3f}", len(moved),
                        "; ".join(f"{k[0]} {k[1]} {d:+,.2f}" for k, d in moved),
                        len(cells_s) - len(fin_cells)])
    with open(RESULTS / "sensitivity_summary.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["decision", "primary_alternative", "alternative", "change_in_q3_total_usd",
                    "change_pct_of_total", "cells_moved", "branch_months_moved", "rows_added_to_output"])
        w.writerows(summary)
    with open(RESULTS / "sensitivity_cells.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["decision", "primary_alternative", "alternative", "branch", "month",
                    "finance_usd", "alternative_usd", "change_usd"])
        w.writerows(cell_rows)

    # D-10 changes only the DQ log: count rows whose bucket depends on the order
    d10 = con.execute("""
        SELECT bucket_if_dedupe_last, count(*) AS rows, sum(ext_cost_usd) AS usd
        FROM (SELECT ext_cost_usd,
                     CASE WHEN trans_date NOT BETWEEN getvariable('period_start') AND getvariable('period_end') THEN 'outside_period'
                          WHEN NOT list_contains(getvariable('rm_group_accounts'), acct) THEN 'not_rm_account'
                          WHEN list_contains(getvariable('rm_capitalised_operations'), oper) THEN 'capitalised_operation'
                          ELSE 'duplicate_copy' END AS bucket_if_dedupe_last
              FROM erp_a_lines WHERE bucket = 'duplicate_copy')
        GROUP BY 1 ORDER BY 1""").fetchall()
    with open(RESULTS / "sensitivity_d10_bucket_order.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["bucket_if_dedupe_tested_last", "rows", "usd"])
        w.writerows(d10)
    print(f"sensitivity: {len(scenarios)} scenarios written")
    return 0


def run_lks_branch(con) -> str:
    return con.execute("SELECT getvariable('erp_b_branch')").fetchone()[0]


def sensitivity_scenarios(jes, period_end, closed_months) -> list[dict]:
    """One primary alternative per decision, plus the other alternatives worth seeing."""
    rm_jes_in_q3 = [j[0] for j in jes if (j[7] or j[8]) and j[1].date() <= period_end]
    rm_jes_all = [j[0] for j in jes if j[7] or j[8]]
    return [
        dict(decision="D-01", primary=True, alternative="De-duplicate exact raw rows only (all columns except ExportedAt)", a={"o_dedupe": "raw_row"}),
        dict(decision="D-01", primary=False, alternative="Keep the earliest copy instead of the latest", a={"o_dedupe": "earliest"}),
        dict(decision="D-01", primary=False, alternative="No de-duplication", a={"o_dedupe": "none"}),
        dict(decision="D-02", primary=True, alternative="ExportedAt as a filter: drop lines from exports after the cut-off", a={"o_period": "transdate_and_cutoff"}),
        dict(decision="D-03", primary=True, alternative="ERP-A slash dates read day-first where valid, else MM/DD (e.g. pandas dayfirst=True)", a={"o_dates": "ddmm_fallback"}),
        dict(decision="D-03", primary=False, alternative="ERP-A slash dates read strictly as DD/MM/YYYY (impossible dates dropped)", a={"o_dates": "ddmm"}),
        dict(decision="D-03", primary=False, alternative="ERP-B dates read as MM/DD/YYYY where valid (spreadsheet-style auto-parse)", b={"o_bdates": "mmdd"}),
        dict(decision="D-04", primary=True, alternative="Whse by first three letters (the profiling lens)", a={"o_whse": "prefix"}),
        dict(decision="D-04", primary=False, alternative="Whse trimmed and upper-cased only (full names unmapped, dropped)", a={"o_whse": "trim_upper"}),
        dict(decision="D-05", primary=True, alternative="Lakeshore R&M per Accounting's account map (7335-RM-HYD excluded)", b={"o_rm": "map"}),
        dict(decision="D-06", primary=True, alternative="Text amounts with thousands separators not parsed (dropped)", b={"o_text": "dropped"}),
        dict(decision="D-06", primary=False, alternative="SUBTOTAL rows kept as postings", b={"o_subtotal": "incl"}),
        dict(decision="D-07", primary=True, alternative="DOUBLE arithmetic with half-even rounding", double=True),
        dict(decision="D-08", primary=True, alternative="Include manual JEs on R&M accounts posted within Q3", jes=[j for j in rm_jes_in_q3]),
        dict(decision="D-08", primary=False, alternative="Include every manual JE on R&M accounts in the September close register, all in September",
             jes=rm_jes_all, je_month="register"),
        dict(decision="D-09", primary=True, alternative="Acct compared as trimmed text ('6100.0' not recognised)", a={"o_acct": "trim_text"}),
        dict(decision="D-09", primary=False, alternative="Acct compared as exact text (' 6100' and '6100.0' not recognised)", a={"o_acct": "exact_text"}),
        dict(decision="D-10", primary=True, alternative="Duplicate bucket tested last instead of first", a={}),
        dict(decision="D-11", primary=True, alternative="DQ log shows indicative USD at the nearest Q3 rate", a={}),
        dict(decision="D-12", primary=True, alternative="Closed branch written as 0.00 for months after its close",
             zero_rows=closed_months),
    ]


if __name__ == "__main__":
    sys.exit(main())
