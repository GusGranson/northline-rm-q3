# Profiling findings: Northline Q3 2026 R&M data pack

Stage: **profile only**. This file reports what is in the raw data. It does not choose treatments. Every number below comes from a CSV in `profiling/results/<source>/`, which `profiling/sql/<source>.sql` produces.

Rerun: `uv run profiling/run_profiling.py` from the repo root. It is read-only, runs in-memory DuckDB 1.5.6, and rewrites every results CSV.

## How to read this

- **Currencies.** ERP-A amounts are USD (ExtCost). ERP-B amounts are CAD (AmountCAD). Nothing has been translated.
- **"R&M accounts" exposure** sizes each issue against group accounts 6100/6150/6200 (README rule 1). These are gross figures before any other treatment, and **they overlap across items**. For example, a September Elmwood line can also sit in the duplicated export. Do not add them up.
- **Measurement lenses.** To count and sum, the profiling SQL reads the raw text through a view that sits next to the raw columns. Nothing is written back. The lenses are assumptions for measurement only, and each one is backed by evidence below:
  - ERP-A slash dates are read as MM/DD/YYYY (see A-4).
  - ERP-A Acct is read as a number, so `' 6100'` and `'6100.0'` are counted as 6100 (A-6).
  - ERP-A Whse is grouped by its first three letters, so `Riverton` and `riv` both count as RIV (A-5).
  - ERP-B dates are read as DD/MM/YYYY (B-4).
  - ERP-B amounts are read with commas stripped (B-2).
- **"in Q3"** means a transaction or posting date from 2026-07-01 to 2026-09-30 under those lenses. The window is set once in `run_profiling.py` (`PARAMS`) as a profiling lens, not as a rule.
- File references: ERP-A `file_line` is the physical CSV line (header = 1). ERP-B `excel_row` is the sheet row (header = 1).

## Summary

| ID | Source | Finding | Rows | Amount | README rule ambiguous? |
|---|---|---|---|---|---|
| A-1 | ERP-A | Export `2026-09-21 06:00` re-pulls every line of `2026-09-19 06:00` | 719 surplus | USD 1,340,417.68 (R&M accts 1,064,327.34) | Silent on dedupe (Q-1) |
| A-2 | ERP-A | Two exports after the README's "last export of the quarter" | 552 | USD 977,423.15 | Partly (Q-2) |
| A-3 | ERP-A | Lines dated outside Q3 | 870 before, 552 after | USD 1,593,576.04 / 977,423.15 | No (rule 3) |
| A-4 | ERP-A | TransDate in two formats; 181 slash dates read two ways | 551 slash (486 in Q3) | USD 919,331.12 in Q3 | Undocumented format (Q-3) |
| A-5 | ERP-A | Whse typed 14 ways for 4 branches | 4,974 non-code in Q3 | USD 8,718,515.24 | Mapping implied, not stated (Q-4) |
| A-6 | ERP-A | Acct with leading space or `.0` suffix | 1,269 in Q3 | R&M accts USD 1,802,195.97 | No |
| A-7 | ERP-A | Elmwood lines dated after its 31-Jul close | 219 (132 on R&M accts) | USD 372,042.96 (R&M 273,819.50) | No (rule 4) |
| A-8 | ERP-A | Capitalised rebuild ops 75/100 on R&M accounts | 185 | USD 429,910.51 | No (rule 2) |
| A-9 | ERP-A | Reversals (negative Qty), 2 crossing months | 67 | USD -178,434.67 | No (rule 3) |
| A-10 | ERP-A | CustNum on R&M-account lines | 4,371 on R&M accts | USD 9,775,391.87 | No (rule 1) |
| B-1 | ERP-B | SUBTOTAL rows mixed in with journal lines | 31 (19 in Q3) | CAD 3,365,648.40 (Q3 3,006,246.65) | Silent (non-data) |
| B-2 | ERP-B | Amounts stored as text with thousands separators | 18 | CAD 51,965.23 | Silent |
| B-3 | ERP-B | Float-representation artefacts in amounts | 29 | n/a (round exactly to cents) | No |
| B-4 | ERP-B | PostingDate stored as DD/MM/YYYY text | 1,504 | n/a | Undocumented format |
| B-5 | ERP-B | Lines posted outside Q3 | 82 before, 70 after | CAD 183,897.88 / 175,503.87 | No (rule 3) |
| B-6 | ERP-B | Local account `7335-RM-HYD` not in account_map | 23 | CAD 108,339.06 | **Yes: rule 6 vs map (Q-5)** |
| B-7 | ERP-B | Negative amounts with no mirrored original | 51 (25 R&M in Q3) | CAD -119,927.70 | No |
| F-1 | FX | Month-end and average rates differ (Sep +0.0175) | 3 | n/a | Rounding mode unstated (Q-7) |
| J-1 | JE register | Two manual JEs on R&M accounts, both after the ERP cut-off | 2 of 7 | USD +18,450.00 / -640.00 | Inclusion not stated (Q-8) |

A-10 on R&M accounts: rows = 2,119 + 843 + 1,409; USD = 6,271,246.85 + 2,852,780.52 + 651,364.50. Source: `erp_a_sro_transactions/15_custnum_by_acct.csv`, all dates.

---

## 1. ERP-A: `erp_a_sro_transactions.csv`

### Shape

- **Rows and columns.** 11,511 data rows plus a header, 13 columns. CRLF line endings, no BOM, no blank lines (`01_file_shape`).
- **Keys.** 2,388 SROs (`S041001` to `S043388`). Line runs 1 to 8.
- **Total.** ExtCost across all rows is USD 20,522,808.31 (`04_amount_precision`).
- **Nulls.** Only `CustNum` has nulls (4,601 rows) (`03_column_profile`).
- **Types as DuckDB's sniffer infers them** (`02_column_types_inferred`):

| Column | Inferred type | Note |
|---|---|---|
| SRO | VARCHAR | |
| Line | BIGINT | |
| Oper | BIGINT | |
| Whse | VARCHAR | |
| **TransDate** | **VARCHAR** | Mixed formats, see A-4 |
| TransType | VARCHAR | |
| **Acct** | **DOUBLE** | `.0` suffixes and leading spaces, see A-6 |
| Item | VARCHAR | |
| Qty | BIGINT | |
| UnitCost | DOUBLE | |
| ExtCost | DOUBLE | |
| CustNum | VARCHAR | |
| ExportedAt | TIMESTAMP | |

**Distinct values.**

- **Oper:** 10, 20, 30, 40, 75, 100.
- **TransType:** Labor, Material, Misc.
- **Acct:** 5100, 6100, 6150, 6200, 6300, 6400, 6500, all in the README group list.
- **CustNum:** C1044, C2087, C3310, or blank.
- **Item:** 16 values, each always on one account.
- **Whse:** 14 raw values (A-5).
- **ExportedAt:** 18 export batches (A-1, A-2).

Files: `05`–`17`.

### A-1 Export `2026-09-21 06:00` is a full re-pull of `2026-09-19 06:00`

**Evidence.**

- **Normal export pattern** (`28_exports_summary`). Exports run weekly on Saturdays at 06:00. Each covers the previous Saturday to Friday, and the windows don't overlap. Two batches break the pattern: `2026-09-21 06:00` (a Monday) and `2026-09-30 18:00` (a Wednesday, the README's quarter cut-off).
- **The two batches are the same size.** `2026-09-19` and `2026-09-21` both hold 719 rows and 221 SROs, both cover transaction dates 2026-09-12..09-18, and both total **USD 1,340,417.68**. Their per-account totals are identical too (`29_exports_by_acct`).
- **Every repeat is this pair.** All 719 SRO+Line pairs in the 09-19 batch appear exactly once in the 09-21 batch. No other SRO+Line repeats anywhere in the file. `36_dup_sro_line_export_pairs` has a single combination, `['2026-09-19 06:00', '2026-09-21 06:00']`, covering 719 groups. No line repeats within one export.
- **Only formatting differs** (`35_dup_sro_line_differing_columns`).
  - Qty, UnitCost, ExtCost, Item, Oper, TransType, CustNum, Acct (as a number) and TransDate (as a date) never differ between the copies.
  - What differs is text formatting. Whse text differs in 488 groups, 218 of them by spelling (`RIV` vs `Riverton`), but the branch prefix is the same in all 719. Acct text differs in 161 groups and TransDate text in 69.
- **Match counts by method:**

| Comparison | Pairs |
|---|---|
| Exact duplicates on all 13 columns | 0 (`31`) |
| Identical on the 12 raw columns other than ExportedAt | 168 (`32`) |
| Identical after normalising format | 501, plus 218 that differ only in Whse spelling (`33`, `34`) |

- **Reversals are duplicated too.** 7 of the 67 reversal rows are 09-21 copies of 09-19 reversals (`40_negative_rows`).

**Sample pairs** (`37_dup_sro_line_variant_rows`, `38_dup_sro_line_identical_samples`):

| SRO / Line | file_line (09-19 → 09-21) | Difference | Content |
|---|---|---|---|
| S041001 / 7 | 804 → 111 | Whse `Oakdale` → `oak`; Acct `6100` → `' 6100'` | Qty -4 × 651.70 = -2,606.80 |
| S041002 / 4 | 2944 → 10775 | TransDate `09/12/2026` → `2026-09-12`; Whse `PIN` → `'PIN '` | 8 × 660.61 = 5,284.88 |
| S043020 / 5 | 3939 → 4603 | Whse `'RIV '` → `RIV` | Reversal, -4,790.37 |

**Exposure.** The surplus is 719 rows and USD 1,340,417.68, all dated in September. Of that, 466 rows and USD 1,064,327.34 are on 6100/6150/6200 (`29_exports_by_acct`).

**Ambiguity.** The README does not say how to treat overlapping or re-pulled exports, which key identifies a line, or which copy to keep. Since the copies agree on every amount and date, the choice of copy doesn't change USD. The choice of key does. → **Q-1**

### A-2 Exports after the README's "last export of the quarter"

**Evidence.**

- The README says the last export of the quarter was pulled 30-Sep-2026 at 18:00. The file has two later batches (`28_exports_summary`):

| Batch | Rows | Transaction dates | USD |
|---|---|---|---|
| `2026-10-03 06:00` | 216 | 2026-10-01..10-02 | 348,153.27 |
| `2026-10-10 06:00` | 336 | all 2026-10-03 | 629,269.88 |

- None of their 552 rows carries a Q3 date, so no Q3-dated line arrived after the cut-off.
- The `2026-09-30 18:00` batch carries dates 09-26..09-30, including 132 lines dated 09-30 (`30_transdate_to_export_lag`, lag 0).
- 2026-10-03 has 336 lines in one day, against 101–132 per day on every other boundary date (`26_transdate_daily_near_boundaries`). It is outside Q3 either way.

**Ambiguity.** Should ExportedAt be a filter in its own right, or only TransDate (rule 3)? In this file both give the same rows. → **Q-2**

### A-3 Lines dated outside Q3

**Evidence** (`25_transdate_by_month`, `27_outside_quarter_by_acct`, `26_transdate_daily_near_boundaries`):

| Window | Dates | Rows | USD | On 6100/6150/6200 |
|---|---|---|---|---|
| Before Q3 | 2026-06-20..06-30 | 870 | 1,593,576.04 | 541 rows, USD 1,251,634.20 |
| After Q3 | 2026-10-01..10-03 | 552 | 977,423.15 | 334 rows, USD 750,037.79 |

- The `2026-07-04` export straddles the boundary, carrying 06-27..07-03.
- The `2026-06-27` export is entirely June.

**In-Q3 totals by month** (all accounts, before any treatment):

| Month | Rows | USD |
|---|---|---|
| Jul | 3,211 | 5,616,760.37 |
| Aug | 3,236 | 5,712,329.93 |
| Sep | 3,642 | 6,622,718.82 |

Rule 3 covers this, so it is not ambiguous.

### A-4 TransDate in two formats

**Evidence.**

- **Formats** (`22_transdate_formats`): 10,960 rows are `YYYY-MM-DD` and 551 are `NN/NN/YYYY`. Every value parses.
- **Slash dates are MM/DD/YYYY** (`23_transdate_slash_ambiguity`). No slash value has a first part above 12. 355 have a second part above 12 (e.g. `06/21/2026`).
- **181 slash values read two ways** (both parts ≤ 12 and different), USD 315,045.84. 15 more read the same either way (`24_transdate_slash_by_reading`).
  - Under MM/DD, 165 of them (USD 289,361.39) fall in Q3.
  - Under DD/MM, 126 of those (USD 217,241.47) would fall outside Q3. For example, `07/01/2026` is Jul-1 or Jan-7.
  - No value moves into Q3 under DD/MM.
- **Slash dates by month under MM/DD:** 486 rows and USD 919,331.12 in Q3 (`25`).
- **Spread:** slash dates appear in every export batch, so this is not one bad batch (`14_acct_raw_format_by_export`).

**Ambiguity.** The README does not state the date format. The MM/DD reading is evidenced but not documented. ERP-B uses the opposite convention (B-4). → **Q-3**

### A-5 Whse typed 14 ways for 4 branch prefixes

**Evidence** (`05_whse_values`, `06_whse_by_month`):

| Branch | Spellings found |
|---|---|
| RIV | `RIV`, `riv`, `'RIV '`, `'Riverton '` |
| OAK | `OAK`, `oak`, `' OAK'`, `Oakdale` |
| PIN | `PIN`, `pin`, `'PIN '`, `Pinecrest` |
| ELM | `ELM`, `Elmwood` |

- 2,483 values have leading or trailing spaces.
- Rows not spelled exactly `RIV`/`OAK`/`PIN`/`ELM`: 5,676 in total, of which 4,974 rows and USD 8,718,515.24 are in Q3.
- **No SRO carries more than one branch** (`18_sro_multi_whse`: 0 rows), so the variants are spelling only.

**Ambiguity.** The README's branch table implies the mapping, but no rule spells it out, in particular for `Elmwood` → ELM, which matters for rule 4. → **Q-4**

### A-6 Acct with leading space or `.0` suffix

**Evidence** (`13_acct_values`).

- 21 raw values cover 7 accounts. 486 rows have a leading space (`' 6100'`) and 948 rows end in `.0` (`'6100.0'`). There are no non-integer values.
- Both formats appear in every export (`14`).

| Format | All accounts in Q3 | On 6100/6150/6200 in Q3 |
|---|---|---|
| Leading space | 429 rows | 253 rows, USD 550,379.45 |
| `.0` suffix | 840 rows | 568 rows, USD 1,251,816.52 |

A text comparison with `'6100'` misses these rows.

Not a rule ambiguity.

### A-7 Elmwood activity after its 31-Jul close

**Evidence** (`06_whse_by_month`, `19_prefix_month_acct`, `21_samples_by_prefix_month`).

- ELM and `Elmwood` lines dated Aug–Sep: 219 rows, USD 372,042.96 (all accounts).

| On 6100/6150/6200 | Rows | USD |
|---|---|---|
| Aug | 70 | 170,257.62 |
| Sep | 62 | 103,561.88 |
| **Total** | **132** | **273,819.50** |

- For comparison, July Elmwood on R&M accounts is 130 rows and USD 268,050.55.
- **Samples:**
  - line 8: S041297, `ELM`, 2026-08-01, 6100, 2,016.84
  - line 347: S042999, `Elmwood`, 2026-09-01, 6100, 2,356.20
- Elmwood also has June and October lines, which are outside Q3.
- No reversal crosses Elmwood's Jul/Aug boundary (A-9).

Rule 4 is explicit, so this is not ambiguous. It depends on Q-4 for which spellings count as Elmwood.

### A-8 Capitalised rebuild operations 75 and 100

**Evidence** (`07`–`10`, `20_samples_by_oper`).

- 185 rows, USD 429,910.51. Every row is dated in Q3 and sits on 6100/6150/6200.

**By operation and account:**

| Op | 6100 | 6150 | 6200 |
|---|---|---|---|
| 75 | 51 rows, 166,363.27 | 28 rows, 91,430.58 | 22 rows, 10,287.54 |
| 100 | 38 rows, 72,886.06 | 22 rows, 76,751.41 | 24 rows, 12,191.65 |

**By month** (USD): Jul 164,763.00 · Aug 127,520.47 · Sep 137,627.04.

- **Dedicated SROs.** These operations occur only on 38 SROs, S043351–S043388, which carry no ops 10–40.
- **No reversals** fall on ops 75/100.
- **Samples:**
  - line 13: S043356, op 75, 6100, 317.22
  - line 158: S043353, op 100, Acct `' 6100'`, 9,215.52
- Some of these lines are in the A-1 duplicated batch, e.g. line 113, S043359, op 100, ExportedAt 09-21.

Rule 2 is explicit, so this is not ambiguous.

### A-9 Reversals (negative quantities)

**Evidence** (`39`–`42`).

- **Sign pattern.** 67 rows, USD -178,434.67. Every one has Qty < 0, UnitCost > 0 and ExtCost < 0. No row has a negative UnitCost, and none has a negative ExtCost with a positive Qty.
- **Where they sit.** All are on 6100/6150/6200, ops 10–40.
- **By month:**

| Month | Rows | USD |
|---|---|---|
| Jul | 19 | -50,746.20 |
| Aug | 24 | -62,823.72 |
| Sep | 24 | -64,864.75 |

- **Each has a matching original.** Every reversal has a candidate original with the same SRO, Oper, Acct, Item and UnitCost and the opposite Qty, on a **different Line number**, as the README describes.
- **Two cross months:**
  - S041809 line 8, dated 2026-08-01, reverses line 4, dated 2026-07-30 (-1,948.55; file_line 5306 → 10234).
  - S042558 line 3, dated 2026-09-01, reverses line 2, dated 2026-08-26 (-177.52; 7777 → 2269).
- No reversal targets a pre-Q3 original.
- 7 reversal rows are A-1 duplicates.

Rule 3 covers this, so it is not ambiguous.

### A-10 Customer numbers on R&M-account lines

**Evidence** (`15_custnum_by_acct`). 6,910 rows carry a CustNum, spread across all seven accounts.

- On 6100 alone, 2,119 rows (USD 6,271,246.85) carry one.
- Conversely, 541 lines on 5100 (billable labor) have no CustNum.

Rule 1 says the account decides, so this is not ambiguous. It is recorded because a CustNum-based "billable" filter would change R&M.

### Checked and clean (ERP-A)

- ExtCost = round(Qty × UnitCost, 2) on all 11,511 rows, with zero mismatches (`43`, `44`).
- Every amount has exactly 2 decimals, and Qty is always an integer (`04`).
- TransType and account always agree: Labor goes to 5100/6200, Material to 6100/6300/6400/6500, Misc to 6150 (`12`).
- No line is dated after the export that carries it (`28`).
- The export lag is 0–7 days, apart from 8–9 days for the A-1 re-pull (`30`).

---

## 2. ERP-B: `erp_b_lakeshore_gl_detail.xlsx`

### Shape

- **Sheet.** One sheet, `GL_Detail`, rows 1–1,505 (header plus 1,504 rows), 6 columns (`01_row_kinds`).
- **Workbook structure.** No hidden rows or columns, no formulas, no merged cells. This came from a one-off openpyxl check, not the runner.
- **Row kinds.** 1,473 journal lines (JournalID `LK88001`–`LK89473`, all distinct) and 31 `SUBTOTAL` rows. There are no blank rows (`07_journalid_shapes`).
- **Inferred types:** AmountCAD DOUBLE, everything else VARCHAR. PostingDate cells are text, not Excel dates (`02`). A typed read of AmountCAD fails (B-2).
- **No branch or currency column.** Every line is implicitly LKS in CAD.
- **Distinct values.**
  - Source: AP, INV, PR on journal lines; empty on SUBTOTAL rows (`11`, `12`).
  - LocalAccount: 7 values (`10`), each with a single Description (`14`).

### B-1 SUBTOTAL rows mixed in with journal lines

**Evidence** (`08_non_data_rows`, `09_subtotal_check`).

- **What they look like.** 31 rows with JournalID `SUBTOTAL`, Description `Subtotal <account> <yyyy-mm>`, PostingDate set to month-end and Source empty. There is one per account per month, including June and October.
- **They tie out exactly.** Every SUBTOTAL equals the journal lines in its block, and the same account-month, with 0.00 difference on all 31.
- **Effect on a naive sum.** SUBTOTAL rows total CAD 3,365,648.40, the same as all journal lines. Summing every row doubles CAD to 6,731,296.80 (`01`).
- **In Q3:** 19 SUBTOTAL rows, CAD 3,006,246.65. Of these, 10 rows (CAD 1,870,331.97) are on 73xx-RM accounts.
- **Sample:** row 1173, `SUBTOTAL`, `30/09/2026`, `7335-RM-HYD`, 108,339.06.

The README is silent here. These are not data rows. Treatment is for the human to decide.

### B-2 Amounts stored as text with thousands separators

**Evidence** (`04_amount_text_shapes`, `05_amount_nonplain_rows`, `06_text_amounts_by_account_month`).

- 18 journal-line cells are text: 17 positive and 1 negative, CAD 51,965.23 in total.
- All are dated in Q3, and all are on R&M local accounts:

| Account | Rows | CAD |
|---|---|---|
| 7310-RM-PARTS | 7 | 17,072.90 |
| 7320-RM-SVC | 5 | 18,778.19 |
| 7330-RM-LAB | 6 | 16,114.14 |

- **Samples:**
  - row 291: `LK88211`, 05/07/2026, `'4,581.93'`
  - row 480: `LK88101`, 23/08/2026, `'-3,287.03'`
- **What goes wrong if they aren't handled.** DuckDB's typed read errors out ("Failed to parse cell 'E291'"). A lenient cast would silently turn all 18 into NULL.
- **Evidence they are real amounts.** The B-1 subtotals tie to the cent only when these are read as numbers.

The README is silent. Treatment is for the human to decide.

### B-3 Float-representation artefacts

**Evidence** (`04`, `05`).

- 29 numeric cells (27 journal lines, 2 subtotals) show binary-float tails, e.g. row 107: `553.5599999999999`.
- All of them round to cents within 1e-6. No value carries real sub-cent precision.

No money impact.

### B-4 PostingDate as DD/MM/YYYY text

**Evidence** (`15_posting_date_formats`, `16_posting_date_ambiguity`).

- All 1,504 values have the shape `NN/NN/YYYY`.
- 936 have a first part above 12, and **none** has a second part above 12, so the format is DD/MM/YYYY.
- 531 values would also parse as MM/DD (CAD 1,213,250.20 of journal lines). The sheet-wide evidence settles them as DD/MM.
- **Range.** Journal lines run from 2026-06-25 to 2026-10-05. SUBTOTALs run from 2026-06-30 to 2026-10-31.
- **Boundary rows.** Journal lines within 3 days of Q3's edges are listed in `18_rows_near_boundaries` (200 rows).

This is the **opposite convention from ERP-A's slash dates** (A-4). The format itself is not stated in the README (→ Q-3).

### B-5 Lines posted outside Q3

**Evidence** (`17_posting_month_by_account`, `19_outside_quarter_summary`).

| Window | Dates | Lines | CAD | On 73xx-RM accounts |
|---|---|---|---|---|
| Before Q3 | 06-25..06-30 | 82 | 183,897.88 | 58 lines, CAD 125,169.95 |
| After Q3 | 10-01..10-05 | 70 | 175,503.87 | 45 lines, CAD 116,615.29 |

Rule 3 covers this, so it is not ambiguous.

### B-6 Local account `7335-RM-HYD` missing from account_map

**Evidence** (`25_localaccount_vs_map`, `13_samples_by_account`, `17`).

| What | Detail |
|---|---|
| Lines and amount | 23 journal lines, CAD 108,339.06 |
| Dates | All in September 2026 (02/09–29/09); no other month |
| Description | "Hydraulic repairs" |
| Sources | AP 9, INV 7, PR 7 |
| Sample rows | 1150 `LK89457` 3,701.20 · 1151 `LK89459` 7,302.60 · 1152 `LK89464` 1,591.14 |

- The code matches 73xx-RM. README rule 6 says every local account in the 73xx-RM range is R&M.
- The account map, which Accounting maintains, has no row for it, so it has no group account.
- It is the only GL account missing from the map, and every map account appears in the GL (`26`).
- **Context.** The 73xx-RM accounts carry CAD 1,870,331.97 in Q3 in total. Of that, CAD 1,761,992.91 is on the three mapped accounts and CAD 108,339.06 on 7335.
- **"73xx-RM range" read two ways.** A strict pattern (`73NN-RM…`) and "7300–7399 with an RM tag" give the same accounts in this data: 7310, 7320, 7330 and 7335.

**Ambiguity.** Rule 6 points one way (R&M) and the map, through its absence, points the other way. The spec says rule 6, but this is exactly the kind of conflict CLAUDE.md says to raise rather than resolve. Separately, if it is R&M, which group account does it belong to (6100/6150/6200)? That doesn't change the Branch/Month output, but it matters for account-level reporting and the bridge. → **Q-5**

### B-7 Negative amounts

**Evidence** (`23_negative_summary`, `24_negative_rows`).

- 51 journal lines, CAD -119,927.70. 25 of them (CAD -62,168.27) are on 73xx-RM accounts in Q3.
- None has a same-account line of the exact opposite amount. They look like credits, not mirrored reversals.

Rule 3 applies: each line counts in its own month. Not ambiguous.

### Checked and clean (ERP-B)

- No exact duplicate lines (`20`).
- No repeated JournalID (`21`).
- No same date/account/description/amount/source under different JournalIDs (`22`).
- No leading or trailing spaces in any column (`03`).

---

## 3. `account_map_lakeshore.csv`

- 6 rows and 3 columns. GroupAccount is inferred as BIGINT (`01`, `02`).
- **No duplicates.** Each local account maps to exactly one group account, one to one (`04`).
- **Contents** (`03_contents`):

| Local account | Group account | Group description |
|---|---|---|
| 7310-RM-PARTS | 6100 | R&M parts |
| 7320-RM-SVC | 6150 | R&M outside service |
| 7330-RM-LAB | 6200 | R&M labor |
| 7500-FLUID | 6300 | Fluids & lubricants |
| 7400-FUEL | 6400 | Fuel off-road |
| 5100-LAB | 5100 | Billable labor |

- Group descriptions match the README's group-account table.
- **Gap:** `7335-RM-HYD` is missing (B-6).

## 4. `fx_cad_usd.csv`

- 3 rows: 2026-07, 2026-08 and 2026-09. Each rate has 4 decimals. No month is missing or duplicated (`02`, `03`).

| Month | Average | Month-end | Month-end − average |
|---|---|---|---|
| 2026-07 | 0.7320 | 0.7290 | -0.0030 |
| 2026-08 | 0.7255 | 0.7240 | -0.0015 |
| 2026-09 | 0.7210 | 0.7385 | **+0.0175** |

- The column names say CAD→USD, so USD = CAD × rate.
- **F-1.** Rule 5 says to use the monthly average. The large September gap means a month-end translation would differ noticeably. That is a candidate reconciling item, not a data defect.
- **Gap in the rule.** Rule 5 doesn't state a rounding mode (half-up vs half-even). → **Q-7**

## 5. `accounting_close_summary.csv`

- One row: `2026-Q3`, "Total R&M, all branches", USD **14,120,360.57** (2 decimals) (`02`).
- No branch, month or account split, and no statement of what is included. Any bridge will start from a single total.

## 6. `accounting_je_register_sep_close.csv`

- 7 entries, posted 2026-09-29 16:02 to 2026-10-02 10:20 (`02_contents`).
- **Missing columns:** no period or effective-date column, and no currency column. The CA entry's description says "Fuel – CAD".

| JE | PostedAt | Entity/Branch | Account | Amount | Description | Notes |
|---|---|---|---|---|---|---|
| JE-0918 | 09-29 16:02 | US / RIV | 6400 | 6,120.33 | Fuel accrual – Sept deliveries | Not an R&M account |
| JE-0921 | 09-29 17:40 | US / OAK | 5100 | -2,210.00 | Reclass billable labor to job 2087 | Not R&M. "2087" echoes CustNum C2087 in ERP-A |
| JE-0925 | 09-30 09:15 | US / PIN | 6500 | 845.10 | Shop supplies – card purchases | Not R&M |
| JE-0927 | 09-30 11:48 | CA / LKS | 7400-FUEL | 3,302.00 (CAD) | Fuel – CAD | Local account; map → 6400, not R&M |
| **JE-0931** | 09-30 **22:14** | US / RIV | **6150** | **18,450.00** | Accrual – outside hydraulic cylinder repair, invoice pending | **R&M account**; posted after the 18:00 ERP-A cut-off |
| JE-0933 | 09-30 23:05 | US / OAK | 6300 | 1,975.40 | Fluids accrual | Not R&M |
| **JE-0940** | **10-02** 10:20 | US / PIN | **6100** | **-640.00** | Vendor credit – bearing return | **R&M account**; posted after quarter end |

- **Totals:** US USD 24,540.83 and CA CAD 3,302.00. These are in different currencies and must not be added (`03_totals_by_account`).
- **No ERP match.** No JE amount equals, in absolute value, any ERP-A ExtCost or ERP-B amount on any date (`04`, `05`). Nothing in the ERP data shows a JE duplicating an ERP line.
- **Context only.** `06` lists ERP-A activity on the same branch and account in the last week of September and the October exports.

**J-1 ambiguity.** Rule 7 is clear: JEs are not an input, and they are reconciling items. But the register doesn't say which entries, if any, are inside Accounting's USD 14,120,360.57. It also gives no effective period for JE-0940, posted 2-Oct in a "Sep close" register. → **Q-8**

---

## Open questions for the human

Items where the README is ambiguous, silent, or in conflict with the data. Each needs a decision before the build. Nothing here has been decided.

| # | Question | Why it matters | Ref |
|---|---|---|---|
| Q-1 | How should re-pulled or overlapping exports be de-duplicated? Which key (SRO+Line, or full line content excluding ExportedAt and formatting), and which copy is kept (first or last export)? | USD 1,340,417.68 surplus (R&M accounts 1,064,327.34). The kept copy's formatting differs but its amounts don't. | A-1 |
| Q-2 | Is ExportedAt ≤ 2026-09-30 18:00 also a filter, or does TransDate alone decide the period? | No effect on this file, since every post-cut-off line is dated October. It is a design choice for reruns. | A-2 |
| Q-3 | Confirm the date formats: ERP-A slash dates as MM/DD/YYYY, ERP-B as DD/MM/YYYY. Neither is documented. | ERP-A: 181 values read two ways (USD 315,045.84). Under DD/MM, USD 217,241.47 would leave Q3. | A-4, B-4 |
| Q-4 | Confirm the Whse → branch mapping, including full names, case and spaces (`Elmwood`/`ELM` → ELM, etc.). | Q3 rows not already spelled as a code: USD 8,718,515.24. Rule 4 depends on recognising Elmwood. | A-5, A-7 |
| Q-5 | `7335-RM-HYD`: does rule 6 (73xx-RM is R&M) override its absence from Accounting's map? If it is R&M, which group account? | CAD 108,339.06, all September. Likely a difference from Accounting. | B-6 |
| Q-6 | ERP-B non-data and malformed cells: confirm SUBTOTAL rows are excluded and text amounts with thousands separators are read as numbers. The README is silent; the subtotal tie-out supports reading them as numbers. | CAD 3,006,246.65 of Q3 subtotals; CAD 51,965.23 of text amounts. | B-1, B-2 |
| Q-7 | FX rounding mode when translating each month's CAD total to cents. | Only changes a result when a value lands on an exact half-cent. | F-1 |
| Q-8 | Which manual JEs are in Accounting's total, and in which period does JE-0940 (posted 2-Oct) sit? | Shapes the bridge. Two JEs touch R&M accounts: +18,450.00 and -640.00. | J-1 |
