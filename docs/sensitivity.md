# Sensitivity: decisions D-01 to D-12

**Six of the twelve decisions are material:** D-01, D-03, D-05, D-06, D-08 and D-09. Swapping any one of them for its most plausible alternative changes the Part 1 file. The largest swings are D-09 (−8.05%) and D-01 (+5.73%), then D-03 (−1.08%). The other six change no number in the file.

## Method

`analysis/scenarios.py` reruns the Part 1 output once per alternative. It uses the same scenario engine that reproduces the actual output to the cent; the script stops if it doesn't.
- Each decision gets one **most plausible alternative**: the treatment a careful analyst could reasonably have chosen instead.
- Other alternatives are shown where they tell you something.
- Each alternative is applied alone, with every other decision as made, so the changes are **not additive**.

Results: `analysis/results/sensitivity_summary.csv` (per alternative) and `sensitivity_cells.csv` (per branch-month).

**Material** here means the alternative moves at least one branch-month of `output/rm_q3_by_branch.csv` by USD 0.01 or more, because that file is checked cell by cell, to the cent. The % column puts each change against the Q3 total of USD 14,090,228.96.

## Most plausible alternative per decision

| Decision | Most plausible alternative | Change in Q3 total (USD) | % of total | Branch-months that move | Material |
|---|---|---:|---:|---|---|
| D-01 De-duplication | De-duplicate exact raw rows only (all columns except ExportedAt) | +807,313.59 | +5.73% | OAK, PIN, RIV 2026-09 | **Yes** |
| D-02 Export cut-off | Use ExportedAt as a filter (drop lines in exports after 30-Sep 18:00) | 0.00 | 0.00% | none | No |
| D-03 Date formats | Read ERP-A slash dates day-first where valid, else MM/DD (pandas `dayfirst=True`) | −152,074.63 | −1.08% | RIV, OAK, PIN, each month (9) | **Yes** |
| D-04 Whse map | Map Whse by its first three letters (the profiling lens) | 0.00 | 0.00% | none | No |
| D-05 7335-RM-HYD | Lakeshore R&M per Accounting's map (7335-RM-HYD excluded) | −78,112.46 | −0.55% | LKS 2026-09 | **Yes** |
| D-06 Subtotals, text amounts | Text amounts with thousands separators not parsed (dropped) | −37,724.23 | −0.27% | LKS 2026-07, 08, 09 | **Yes** |
| D-07 DECIMAL, half-up | DOUBLE arithmetic with half-even rounding | 0.00 | 0.00% | none | No |
| D-08 Manual JEs | Include manual JEs on R&M accounts posted within Q3 | +18,450.00 | +0.13% | RIV 2026-09 | **Yes** |
| D-09 Account codes | Compare Acct as trimmed text (`6100.0` not recognised) | −1,134,261.79 | −8.05% | all 10 ERP-A branch-months | **Yes** |
| D-10 Bucket order | Test the duplicate bucket last instead of first | 0.00 | 0.00% | none (data quality log only) | No |
| D-11 USD without a rate | Show indicative USD at the nearest Q3 rate | 0.00 | 0.00% | none (data quality log only) | No |
| D-12 No ELM rows after July | Write ELM 2026-08 and 2026-09 as 0.00 | 0.00 | 0.00% | none; the file gains 2 rows | No (file shape only) |

The "all 10 ERP-A branch-months" are RIV, OAK and PIN for July to September, plus ELM July.

Cell-level moves for the material decisions:

- **D-01:**
  - OAK 2026-09 +231,792.73
  - PIN 2026-09 +285,687.10
  - RIV 2026-09 +289,833.76
- **D-03:** only the 181 slash dates that read either way change. Some leave Q3 and some move month. Eight cells fall, from PIN 2026-08 (−9,281.43) to RIV 2026-07 (−30,059.15). RIV 2026-08 rises by +8,847.12 as dates move into August. ELM is unchanged.
- **D-05:** LKS 2026-09 −78,112.46.
- **D-06:** LKS 2026-07 −14,056.69, 2026-08 −7,426.70, 2026-09 −16,240.84.
- **D-08:** RIV 2026-09 +18,450.00 (JE-0931).
- **D-09:** every ERP-A cell falls, from ELM 2026-07 (−40,831.75) to OAK 2026-09 (−166,157.13).

## Other alternatives tested

| Decision | Alternative | Change in Q3 total (USD) | % of total | Note |
|---|---|---:|---:|---|
| D-01 | Keep the earliest copy instead of the latest | 0.00 | 0.00% | The copies agree on every amount and date. |
| D-01 | No de-duplication | +1,043,815.38 | +7.41% | The full surplus that the key removes. |
| D-03 | Read ERP-A slash dates strictly as DD/MM/YYYY (impossible dates dropped) | −587,637.33 | −4.17% | Also loses the 355 slash dates that can't be DD/MM. Every ERP-A cell falls. |
| D-03 | Read ERP-B dates as MM/DD/YYYY where valid (spreadsheet-style auto-parse) | −351,340.03 | −2.49% | All three LKS months fall. |
| D-04 | Trim and upper-case Whse only (full names unmapped, dropped) | −2,151,968.59 | −15.27% | The naive alternative. Every ERP-A cell falls. |
| D-06 | Keep SUBTOTAL rows as postings | +1,357,479.63 | +9.63% | Doubles Lakeshore. |
| D-08 | Include every R&M JE in the September close register, all in September | +17,810.00 | +0.13% | Adds JE-0940 (PIN 2026-09 −640.00). |
| D-09 | Compare Acct as exact text (`' 6100'` and `'6100.0'` not recognised) | −1,627,624.69 | −11.55% | Every ERP-A cell falls. |

## Reading the table

**Material decisions:**
- **D-01 and D-09** are the large ones: 5.7% and 8.1% of the quarter. **D-03** is 1.1%, and 4.2% if the alternative parser drops impossible dates. Each is a choice about reading the raw data, and each is where the profiling evidence did the work:
  - D-01: the re-pulled export.
  - D-03: no slash date has a first part above 12.
  - D-09: the `.0` suffixes.
- **D-05 and D-06** are smaller but not small. Both sit in Lakeshore's September (D-05) or across Lakeshore's quarter (D-06).
  - The bridge shows Accounting also includes 7335-RM-HYD. So D-05's alternative would widen the gap to Accounting, not close it.
- **D-08's alternative is exactly bridge item R1.** Under README rule 7, Finance excludes the JE. Including it would make Finance's number match Accounting's definition rather than the README's.

**Not material, but for different reasons:**
- **D-02:** no Q3 line arrived after the cut-off. The decision protects future reruns, not this quarter.
- **D-04:** the prefix lens happens to give the same branches on this file. The decision's value is governance: a new spelling now fails the build instead of mapping by guesswork. The naive alternative (trim and upper case only) would be the single largest error in the table, at −15.27%.
- **D-07:** no translated month lands on a half cent, and DOUBLE sums of two-decimal amounts round back exactly at this scale. The decision guards against a 0.01 break, which this quarter doesn't trigger.
- **D-10:** changes only how the data quality log attributes rows. Tested last, the duplicate bucket would shrink from 719 rows (USD 1,340,417.68) to 455 rows (USD 1,043,815.38). Of the 264 rows that leave it, 253 (USD 276,090.34) would move to `not_rm_account` and 11 (USD 20,511.96) to `capitalised_operation` (`sensitivity_d10_bucket_order.csv`).
- **D-11:** affects only the data quality log.
- **D-12:** changes the file's shape (15 rows instead of 13) but no value.
