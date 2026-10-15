# Verification: independent rebuild vs pipeline

**Result: identical to the cent.** All 39 cells of `verify/verify_rm_q3_by_branch.csv` match `output/rm_q3_by_branch.csv` (13 rows × 3 columns), in the same row order. Both total USD 14,090,228.96. The files differ only in line endings.

Compared on 2026-10-15 against the pipeline output at commit `3b72320`.

## What the verify was given, and what it wasn't

The verify is an independent build of the same spec by a different model (Sonnet). It is the script `verify/build_rm_q3.py` (80 lines, plain Python with `csv`, `Decimal` and openpyxl; no DuckDB). Its notes are in `verify/verify_notes.md`.

| | Detail |
|---|---|
| **Given** | The raw data files, `data/raw/README.md` and `docs/decisions.md` (D-01 to D-12). Its script reads `erp_a_sro_transactions.csv`, `erp_b_lakeshore_gl_detail.xlsx` and `fx_cad_usd.csv`. |
| **Not given** | Our code (`sql/`, `run.py`), config (`config/*.toml`), outputs, and `profiling/findings.md`. |
| **Absent from its folder** | `accounting_close_summary.csv` and `accounting_je_register_sep_close.csv` (its note 1). |
| **Not used** | `account_map_lakeshore.csv`: the script never reads it. |
| **From its task brief** | The output columns and formats (Branch, Month, RM_USD) are not defined in the README or decisions.md, so they came with its brief. |

**What this means.** The verify is an independent *implementation* of the same rules and decisions. It is not an independent *judgment* of the treatments, because it was handed D-01 to D-12. Its implementation differs from ours at every layer that could hide a bug: model, language, CSV parser, xlsx reader and decimal library. A match therefore tests our code. It does not test our decisions.

## How the comparison was done

1. **Reproduced its output.** Its script was rerun on a scratch copy of its three input files. The new CSV is byte-identical to the delivered `verify_rm_q3_by_branch.csv`.
2. **Compared the files cell by cell** in plain Python (`csv` and `Decimal`), deliberately not DuckDB, so the comparison doesn't share the pipeline's tooling. In order:
   - the header
   - row count and the set of (Branch, Month) keys
   - row order
   - every cell as text
   - the numeric difference per row

| Branch | Month | Pipeline (USD) | Verify (USD) | Difference |
|---|---|---:|---:|---:|
| RIV | 2026-07 | 1,522,852.26 | 1,522,852.26 | 0.00 |
| RIV | 2026-08 | 1,540,190.70 | 1,540,190.70 | 0.00 |
| RIV | 2026-09 | 1,326,944.21 | 1,326,944.21 | 0.00 |
| OAK | 2026-07 | 1,310,446.01 | 1,310,446.01 | 0.00 |
| OAK | 2026-08 | 1,478,995.18 | 1,478,995.18 | 0.00 |
| OAK | 2026-09 | 1,579,502.88 | 1,579,502.88 | 0.00 |
| PIN | 2026-07 | 1,145,925.90 | 1,145,925.90 | 0.00 |
| PIN | 2026-08 | 1,350,571.29 | 1,350,571.29 | 0.00 |
| PIN | 2026-09 | 1,209,270.36 | 1,209,270.36 | 0.00 |
| ELM | 2026-07 | 268,050.55 | 268,050.55 | 0.00 |
| LKS | 2026-07 | 400,642.79 | 400,642.79 | 0.00 |
| LKS | 2026-08 | 475,554.34 | 475,554.34 | 0.00 |
| LKS | 2026-09 | 481,282.49 | 481,282.49 | 0.00 |
| **Total** | | **14,090,228.96** | **14,090,228.96** | **0.00** |

**Summary of checks:**
- Header identical: `Branch,Month,RM_USD`.
- 13 rows in each file.
- No key appears in only one file.
- Row order identical.
- 0 of 39 cells differ as text.

**File bytes.** The files are not byte-identical, but only because of line endings. The verify writes CRLF (Python's `csv` default; 329 bytes) and the pipeline writes LF (315 bytes). The 14-byte gap is one carriage return per line. Content is identical.

## Its calls (`verify_notes.md`)

`verify_notes.md` lists **six** items under "Not covered by README/decisions — my calls", not three. Reading them against the README and decisions.md:

- **Three are genuinely calls those documents don't settle:** #2, #3 and #5.
- **The other three restate a rule or decision, or describe scope:** #1, #4 and #6.

All six are assessed below.

### The three undocumented calls

**#2 · ExtCost used as given, not recomputed from Qty × UnitCost; reversals taken at their posted sign.**
- **Covered by README/decisions?** No.
- **Our pipeline:** Same. ExtCost is cast to cents at staging (`sql/01_stage_erp_a.sql`). Reversals count at their posted negative ExtCost in their own month: DQ log A10 shows 60 kept reversal lines totalling USD −156,212.59. The DQ control A12 finds ExtCost = round(Qty × UnitCost, 2) on all 11,511 rows, so recomputing would not change anything.
- **Agrees?** Yes.

**#3 · 7335-RM-HYD matched by the pattern `73\d\d-RM(-...)?`; it has no group account.**
- **Covered by README/decisions?** Partly. README rule 6 and D-05 say the 73xx-RM range decides and that no group account is assigned. The exact pattern is not written in decisions.md; ours lives in `config/rules.toml`.
- **Our pipeline:** Uses `^73[0-9]{2}-RM`. Both patterns select exactly 7310, 7320, 7330 and 7335 out of the seven local accounts in the GL.
- **Agrees?** Yes, on this data. On hypothetical codes ours is looser: it would also accept `7340-RMX` or `7340-RM2`, and the verify's would not. That is a note for Finance, who own `rules.toml`. Nothing was changed.

**#5 · Output sorted by branch (RIV, OAK, PIN, ELM, LKS), then month.**
- **Covered by README/decisions?** No. Neither fixes an order, and the exercise doesn't either.
- **Our pipeline:** Same order. Branch order comes from `branches.codes` in `config/pipeline.toml`, which follows the README table, then month.
- **Agrees?** Yes. Row order is identical.

### The other three

**#1 · The accounting close summary and JE register are absent; no bridge was done.**
- **Covered by README/decisions?** Yes: rule 7 and D-08.
- **Our pipeline:** Same. Neither file is a build input; the bridge is a later stage.
- **Agrees?** Yes.

**#4 · ERP-B float noise removed via `repr()` then quantised to cents; D-07's tolerance not asserted.**
- **Covered by README/decisions?** Yes: D-07.
- **Our pipeline:** Same cents. Check C12 also enforces D-07's tolerance (less than 0.000001 removed per value).
- **Agrees?** On values, yes. The verify skips D-07's check.

**#6 · Dedupe before the period filter, using D-10's bucket order; no DQ log.**
- **Covered by README/decisions?** Yes: D-10.
- **Our pipeline:** Same bucket order. The DQ log is produced in `output/dq_log.csv`.
- **Agrees?** Yes. Not producing a DQ log is a difference of scope only.

## Differences found by reading its script (not in its notes)

None of these changes a number on this data. They show where the verify's checks are narrower than the pipeline's:

- **D-02 check tests a different copy.** The verify checks the ExportedAt of the *kept (latest)* copy of a Q3 line. D-02 and our check C08 test where a line *first* appears. A Q3 line that was re-pulled after the cut-off would abort the verify but pass ours. No Q3 line is in a post-cut-off export: all 552 lines in those exports are dated October (DQ A02, check C08).
- **Mapping checks cover fewer rows.** The verify checks for unmapped Whse values and unknown accounts only on kept Q3 R&M lines. Ours (C02, C03) checks all 11,511 rows.
- **Account parsing can truncate.** `int(Decimal(Acct))` would turn a value like `6100.7` into 6100 without complaint; ours fails C03 on it.
- **JournalID check is looser.** The verify only requires the ID to start with `LK`; ours requires `^LK[0-9]+$`.
- **Some controls are missing.** The verify has no row conservation and no DQ log. A missing FX rate would surface as a Python KeyError rather than a named check.

## What this proves, and what it doesn't

**Proves:** Two independent implementations apply the README rules and D-01 to D-12 to the same raw data and agree to the cent on all 13 branch-months.

**Doesn't prove:**
- **That the decisions are right.** Both builds were given them.
- **That the Whse map is complete beyond this file.** Both builds took the 14 values from D-04.
- **Anything about the bridge to Accounting's USD 14,120,360.57.** That is the next stage, and the verify had no accounting files.
