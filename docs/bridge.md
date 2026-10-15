# Bridge: Finance to Accounting, Q3 2026 R&M (Part 3)

**Two items bridge Finance's USD 14,090,228.96 to Accounting's USD 14,120,360.57 to the cent:**
- **Manual JE-0931:** an accrual Accounting booked after the ERP cut-off.
- **Lakeshore September FX:** translated by Accounting at the month-end rate instead of the average.

The residual is 0.00. Out of 77,856,768 combinations of plausible Accounting methods tested, this is the only one that closes exactly.

| Step | Item | Branch | Month | USD | Running total |
|---:|---|---|---|---:|---:|
| 0 | Finance R&M (sum of `output/rm_q3_by_branch.csv`) | | | 14,090,228.96 | 14,090,228.96 |
| 1 | R1 · Manual JE-0931: accrual for outside hydraulic cylinder repair, invoice pending | RIV | 2026-09 | +18,450.00 | 14,108,678.96 |
| 2 | R2 · Lakeshore September translated at month-end 0.7385 instead of average 0.7210 | LKS | 2026-09 | +11,681.61 | 14,120,360.57 |
| | Accounting R&M as reported (`accounting_close_summary.csv`) | | | 14,120,360.57 | |
| | **Residual** | | | **0.00** | |

**Where the bridge lives**
- **Code:** `sql/09_bridge.sql`. Every item is computed from a source record: a JE in the register, or a month of Lakeshore CAD and the FX file. Nothing is set to the residual.
- **Output:** `output/bridge.csv`.
- **Checks:**
  - C25 fails the build unless the residual is exactly 0.00.
  - C26 fails it unless every item traces to a JE or an FX month, i.e. no plugs.
- **The check bites:** I ran the build without the September FX observation (in a scratch copy of the config), and C25 failed with a residual of 11,681.61.

## How the items were found

`analysis/scenarios.py` builds the pipeline tables exactly as `run.py` does. It then re-scores the quarter under alternative methods. Its engine, run with Finance's treatments, reproduces all 13 cells of the Part 1 output to the cent before anything else runs.

The search covered every combination of:

| Dimension | Alternatives tested |
|---|---|
| Manual JEs | Each of the 7 in or out. JE-0927 is in CAD, so it is translated at the rate chosen for its month. |
| FX | Average or month-end rate for each month separately; the Q3 CAD total at September's month-end rate; the Q3 CAD total at September's average; each month at the mean of the three averages. |
| Lakeshore R&M scope | The 73xx-RM range (Finance) or Accounting's account map (7335-RM-HYD excluded). |
| Each data quality treatment not applied | Duplicate export kept; out-of-period lines kept; period by export date instead of transaction date; slash dates read DD/MM (strictly, or day-first with a fallback) or dropped; Acct compared as text; Whse mapped by trim/upper case only, or exact codes only; capitalised operations kept (both, or either one); reversals dropped; customer lines dropped; text amounts dropped; SUBTOTAL rows kept; ERP-B dates read MM/DD. |

**Result:**
- **Exactly one combination closes:** JE-0931 included plus September at the month-end rate. Every other treatment matches Finance's (`analysis/results/bridge_closing_combinations.csv`).
- **The nearest misses are far less plausible.** They miss by USD 0.04 and 0.05, and each needs 11 simultaneous deviations, such as keeping the duplicate export, dropping reversals and keeping SUBTOTAL rows (`bridge_nearest_misses.csv`).
- **Single-candidate effects** are in `bridge_single_effects.csv`.

## R1 · JE-0931 accrual: +18,450.00 (RIV, 2026-09)

**Evidence**
- JE-0931 sits in Accounting's September close register: RIV, account 6150 (R&M outside service), USD 18,450.00, "Accrual – outside hydraulic cylinder repair, invoice pending".
- It was posted 30-Sep-2026 at 22:14, four hours after the last ERP-A export of the quarter (18:00).
- No ERP-A line in any export, on any date, carries that amount (`profiling/findings.md` J-1). So the cost is not in the ERP data in another form.
- The search needs it included to close. JE-0940, posted on 2 October, is not included.

**Who is right:** both, under their own definitions.
- **Finance:** README rule 7 builds Finance's R&M from ERP data only and treats manual JEs as reconciling items. So Finance is right to leave it out.
- **Accounting:** it is right to accrue a service received in September whose invoice hasn't arrived. That is ordinary accrual accounting, not an error.

**What should change, and where**
- **Neither total changes.** The item stays a disclosed reconciling item.
- **Accounting:** reverse JE-0931 in October when the invoice posts in ERP-A (RIV, 6150), so the cost isn't counted twice in Q4.
- **Finance:** confirm the invoice line lands in ERP-A in October. Until it does, Q4 carries the same timing difference in reverse.

## R2 · Lakeshore September at the month-end rate: +11,681.61 (LKS, 2026-09)

**Evidence**
- Lakeshore's September R&M is CAD 667,520.79, including 7335-RM-HYD:
  - at the September average rate (0.7210): USD 481,282.49, which is Finance's figure;
  - at the month-end rate (0.7385): USD 492,964.10.
- The difference is USD 11,681.61.
- July and August must be at the average rate for the bridge to close. At month-end they would move by −1,641.98 and −983.23, and no combination using them closes.
- So Accounting used the right rate for two months and the balance-sheet rate for the quarter-end month. The likeliest cause is the September close picking up the month-end rate for P&L translation. That is an inference: the data shows which rate was used, not why.

**Who is right:** Finance. README rule 5 (group policy for P&L) translates Lakeshore at the monthly average rate.

**What should change, and where**
- **Accounting:** re-translate Lakeshore's September R&M at 0.7210 in the September close (Lakeshore's P&L translation). This lowers Accounting's Q3 R&M by 11,681.61, to **USD 14,108,678.96**.
- **To prevent a repeat:** keep one governed rate table with the rate type per use. P&L lines should always take the average; Finance's own rule is in `config/rules.toml` (`[fx] rate_column`).

## Candidates that are not reconciling items

Each was tested alone and in every combination. Accounting's total matches Finance's treatment on all of them.

| Candidate | Effect if Accounting had done it | Why it is not an item |
|---|---:|---|
| JE-0940, vendor credit on PIN 6100, posted 2-Oct | −640.00 | Posted after quarter end. It is in neither Q3 total. |
| JE-0918, -0921, -0925, -0927, -0933 | +6,120.33, −2,210.00, +845.10, +2,380.74, +1,975.40 | Not R&M accounts (6400, 5100, 6500, 7400-FUEL → 6400, 6300). None is in Accounting's R&M. |
| 7335-RM-HYD excluded per Accounting's map | −78,112.46 | Accounting's total includes it: the only close needs it in, at September's month-end rate. |
| July or August at month-end | −1,641.98 / −983.23 | Accounting used the average in both months. |
| Whole-quarter FX methods | +23,760.54, −8,970.27, +693.12 | None closes. |
| Duplicate export (2026-09-21) kept | +1,043,815.38 | Accounting de-duplicated too. |
| Capitalised operations 75/100 kept | +409,398.55 | Accounting excluded them too. |
| Text amounts with thousands separators dropped | −37,724.23 | Accounting read them. |
| SUBTOTAL rows kept | +1,357,479.63 | Accounting excluded them. |
| Any other data quality treatment not applied | 156,212.59 to 7,670,610.69 in size | None is consistent with Accounting's total. |

7335-RM-HYD deserves a note. D-05 expected it to be a bridge item, and it isn't one: Accounting's total already contains it. The account-map gap still needs fixing, because the map is how Accounting classifies Lakeshore accounts. But it has no dollar effect on this quarter's bridge.

## Is Accounting's figure right?

Not quite. It overstates Q3 R&M by USD 11,681.61 because September's Lakeshore costs were translated at the month-end rate (R2). Corrected, Accounting's figure is USD 14,108,678.96. The remaining USD 18,450.00 against Finance is the JE-0931 accrual (R1). That is a definitional and timing difference under README rule 7, not an error on either side.

## Limits

- **The search covers the methods listed above.** A method outside them could in principle also close. But the close found needs only two simple deviations, and no other combination comes closer than USD 0.04.
- **Accounting's method is inferred from the arithmetic.** Two points should be confirmed with Accounting: the rate used in the September close, and the cut-off for manual JEs.
- **The JE register has no effective-date column.** JE-0940's period is inferred from its posting date (2 October).
