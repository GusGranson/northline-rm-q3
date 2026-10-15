# Decisions: Northline Q3 R&M

Human decisions on how the build treats the data. Each entry gives the decision, the evidence (from `profiling/findings.md`) and where it is enforced. Rule values live only in `config/rules.toml`; this file records why they are what they are.

Decided by Gus on 2026-10-15, after profiling.

## Treatment decisions

### D-01 · ERP-A de-duplication (findings A-1, Q-1)
- **Decision:** An ERP-A line is identified by SRO + Line. When a line appears in more than one export, keep the copy with the latest ExportedAt and drop the others.
- **Why:** Export 2026-09-21 06:00 repeats all 719 lines of 2026-09-19 06:00 (USD 1,340,417.68). SRO + Line is unique within every export, and every reversal has its own Line number, so the key cannot merge a reversal into its original. Latest-wins is the standard snapshot convention. The copies agree on every amount and date, so the choice of copy does not move USD.
- **Enforced by:** `[erp_a] dedupe_key`, `dedupe_keep` in config. Check: SRO + Line is unique after de-duplication. The DQ log reports the dropped copies (rows, USD).

### D-02 · TransDate decides the period; the export cut-off is a check (A-2, Q-2)
- **Decision:** TransDate alone decides the period (README rule 3). ExportedAt is not a filter.
- **Why:** In this file every line in the exports after 2026-09-30 18:00 is dated October, so both approaches select the same rows. On a future rerun, a filter would silently drop late-arriving Q3 lines; a check surfaces them.
- **Enforced by:** Assertion: no line with a Q3 TransDate first appears in an export pulled after the README cut-off (2026-09-30 18:00). The build fails if one does.

### D-03 · Date formats (A-4, B-4, Q-3)
- **Decision:** ERP-A TransDate is `YYYY-MM-DD` or `MM/DD/YYYY`. ERP-B PostingDate is `DD/MM/YYYY`. This is an evidenced assumption; neither format is documented.
- **Why:** In ERP-A, no slash date has a first part above 12 and 355 have a second part above 12. In ERP-B, 936 have a first part above 12 and none has a second part above 12. It also fits a US ERP and a Canadian one. The 181 ERP-A values that read either way (USD 315,045.84) are read as MM/DD on that evidence.
- **Enforced by:** Date formats per source in config. The build fails on any date that does not parse in its listed formats.

### D-04 · Whse to branch mapping (A-5, Q-4)
- **Decision:** An explicit table maps each raw Whse value, exactly as typed (case and spaces included), to a branch code. A value missing from the table fails the build. This replaces the three-letter lens used in profiling.

  | Raw Whse | Branch |
  |---|---|
  | `RIV`, `riv`, `'RIV '`, `'Riverton '` | RIV |
  | `OAK`, `oak`, `' OAK'`, `Oakdale` | OAK |
  | `PIN`, `pin`, `'PIN '`, `Pinecrest` | PIN |
  | `ELM`, `Elmwood` | ELM |

- **Why:** The prefix lens is a heuristic. An explicit map is what would be governed for real, and a new spelling breaks loudly instead of mapping silently.
- **Enforced by:** `[erp_a] whse_map` in config, plus an assertion on unmapped values. README rule 4 (Elmwood from 1-Aug goes to OAK) is applied after this mapping.

### D-05 · Lakeshore 7335-RM-HYD is R&M (B-6, Q-5)
- **Decision:** Include 7335-RM-HYD as R&M. README rule 6 (every local account in the 73xx-RM range is R&M) decides, not the account map. No group account is assigned, because the Branch/Month output does not need one.
- **Why:** The spec says the account range decides. Accounting maintains the map, so the missing row is an Accounting map gap.
- **Fix-where:** Accounting adds 7335-RM-HYD to `account_map_lakeshore`. Expected to be a bridge item: CAD 108,339.06, about USD 78,112 at the September average rate. The bridge gives the exact figure.
- **Enforced by:** `[erp_b] rm_local_account_pattern` in config. The DQ log reports local accounts that match the pattern but are missing from the map (rows, CAD, USD). Check: for every account in the map, the pattern and the map agree on whether it is R&M.

### D-06 · ERP-B subtotal rows and text amounts (B-1, B-2, Q-6)
- **Decision:** Exclude SUBTOTAL rows. Read amounts stored as text with thousands separators as numbers.
- **Why:** SUBTOTAL rows repeat the journal lines (CAD 3,365,648.40), so keeping them doubles the total. The 18 text amounts (CAD 51,965.23) are real postings: the subtotals tie to the cent only when those amounts are included.
- **Enforced by:** The subtotals become a control. After parsing, each SUBTOTAL must equal the journal lines for its account and month, or the build fails. The build also fails if any remaining row lacks an `LK` JournalID or has an amount that does not parse.

### D-07 · DECIMAL arithmetic, half-up rounding (B-3, Q-7)
- **Decision:** Cast every amount to DECIMAL(18,2) at staging and keep FX rates as DECIMAL. There is no DOUBLE arithmetic anywhere. Round half-up. For Lakeshore, each month's CAD total is multiplied by that month's average rate and rounded to cents (README rule 5).
- **Why:** DECIMAL matters more than the rounding mode. The xlsx already shows float tails (B-3), and DOUBLE math is how a to-the-cent bridge ends up 0.01 off.
- **Note:** DuckDB rounds DECIMAL half away from zero (0.125 → 0.13, −0.125 → −0.13). That equals half-up for positive amounts, and the Lakeshore monthly totals being translated are positive.
- **Enforced by:** Check: the cast to DECIMAL(18,2) may only remove float noise (each value differs from its source text by less than 0.000001). Otherwise the build fails.

### D-08 · Manual journal entries (J-1, Q-8)
- **Decision:** Deferred to the bridge. JEs are not an input to Finance's R&M (README rule 7). Accounting's total has no breakdown, so the bridge arithmetic will show which JEs it includes. That result is recorded here then.

## Build conventions (proposed by Claude, confirmed by Gus)

### D-09 · ERP-A account codes (A-6)
- **Decision:** Read Acct as an integer after trimming spaces and a trailing `.0` (`' 6100'` and `'6100.0'` both become 6100). The build fails on any Acct that is not one of the README group accounts.
- **Why:** 1,434 rows carry these formats. A text match on `'6100'` would miss USD 1,802,195.97 of Q3 lines on R&M accounts.

### D-10 · One exclusion bucket per row
- **Decision:** For row conservation and the DQ log, each raw row lands in exactly one bucket. Buckets are tested in this order:
  - ERP-A: duplicate copy → outside Q3 → not an R&M account → capitalised operation (75/100) → kept.
  - ERP-B: SUBTOTAL row → outside Q3 → not 73xx-RM → kept.
- Some treatments change no row count: the Elmwood → Oakdale reassignment, format normalisation and the text amounts. The DQ log reports those with rows and USD affected, but they are not buckets.
- **Why:** An exclusive order makes raw = kept + sum of buckets exact. Each bucket's USD is then what that rule removed after the earlier rules ran.

## Build questions (asked by Claude, decided by Gus)

### D-11 · USD for Lakeshore amounts in months without a rate (DQ log only)
- **Decision:** In the data quality log, Lakeshore amounts dated in a month with no rate in `fx_cad_usd.csv` (June, October) are reported in CAD only. USD is left blank with the reason "no CAD/USD rate in the data pack for this month". The DQ check accepts a blank USD only with that reason.
- **Why:** No rule defines a rate for those months, and the amounts never reach the output, so no rate is invented.

### D-12 · Elmwood after July in the output
- **Decision:** The output has no ELM rows for 2026-08 or 2026-09. Under README rule 4, all Elmwood activity from 1-Aug is reported under OAK, so ELM has no reporting months after July. The file has 13 rows.
- **Why:** A zero row would read as "Elmwood had no R&M", when in fact its activity is reported under Oakdale.
