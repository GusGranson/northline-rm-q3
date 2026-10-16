# Northline Q3 2026 Repair & Maintenance: submission report

Prepared for Finance. Period: Q3 2026 (1 July to 30 September 2026).

## Answer

Finance's Q3 2026 R&M, built from ERP data under the README rules, is **USD 14,090,228.96**. Accounting reports **USD 14,120,360.57**. Two items explain the difference of USD 30,131.61 in full:

| | USD |
|---|---:|
| Finance Q3 R&M | 14,090,228.96 |
| JE-0931: manual accrual for an outside hydraulic cylinder repair (RIV, September), in Accounting's total only | +18,450.00 |
| Lakeshore September translated by Accounting at the month-end rate (0.7385) instead of the monthly average (0.7210) | +11,681.61 |
| **Accounting Q3 R&M as reported** | **14,120,360.57** |
| Residual | 0.00 |

Accounting's figure is overstated by USD 11,681.61 because of the September exchange rate; corrected, it is USD 14,108,678.96. The remaining USD 18,450.00 is a definitional difference: Finance's R&M excludes manual journal entries (README rule 7), while the accrual is valid in the general ledger.

**Basis of confidence**
- The build fails unless all 27 checks pass, including row and amount conservation and a bridge residual of exactly 0.00 ([output/checks.csv](output/checks.csv)).
- An independent rebuild by a different model, given only the raw files, the README and the decisions, matches all 13 branch-month figures to the cent ([verify/comparison.md](verify/comparison.md)).
- Of 77,856,768 combinations of plausible Accounting methods tested, only the bridge above closes exactly ([docs/bridge.md](docs/bridge.md)).

## Part 1 · Q3 R&M by branch and month

| Branch | 2026-07 | 2026-08 | 2026-09 | Q3 |
|---|---:|---:|---:|---:|
| RIV | 1,522,852.26 | 1,540,190.70 | 1,326,944.21 | 4,389,987.17 |
| OAK | 1,310,446.01 | 1,478,995.18 | 1,579,502.88 | 4,368,944.07 |
| PIN | 1,145,925.90 | 1,350,571.29 | 1,209,270.36 | 3,705,767.55 |
| ELM | 268,050.55 | – | – | 268,050.55 |
| LKS | 400,642.79 | 475,554.34 | 481,282.49 | 1,357,479.62 |
| **Total** | **4,647,917.51** | **4,845,311.51** | **4,596,999.94** | **14,090,228.96** |

- **File:** [output/rm_q3_by_branch.csv](output/rm_q3_by_branch.csv) (Branch, Month, RM_USD). The table above reshapes it; the totals are sums of its rows.
- **Elmwood:** closed on 31 July 2026. Its August and September activity is reported under Oakdale (README rule 4), so Elmwood has no rows after July (D-12).
- **Lakeshore:** translated from CAD at each month's average rate and rounded to cents (README rule 5).
- **Treatments:** each is recorded with its evidence in [docs/decisions.md](docs/decisions.md). The effect of each on these figures is in [docs/sensitivity.md](docs/sensitivity.md).

## Part 2 · Data quality log

This is a summary of [output/dq_log.csv](output/dq_log.csv). Profiling evidence for each issue is in [profiling/findings.md](profiling/findings.md).

**How to read the amounts:**
- ERP-A amounts are in USD.
- Lakeshore (ERP-B) amounts are translated at the monthly average where a rate exists. The data pack has no rate for June or October, so those amounts remain in CAD (D-11).
- "USD" is the amount of the affected rows across all accounts, not the effect on R&M.

**Data issues found (10)**

| ID | Issue | Detection | Rule applied | Rows | USD |
|---|---|---|---|---:|---:|
| A01 | The 21 September export repeats every line of the 19 September export | SRO and Line seen in more than one export | Keep the latest copy, drop the others (D-01) | 719 | 1,340,417.68 |
| A02 | Lines in exports pulled after the stated cut-off (30 September, 18:00) | Export time after the cut-off | No change: the transaction date decides the period. All are dated October (D-02) | 552 | 977,423.15 |
| A04 | Transaction dates in MM/DD/YYYY alongside YYYY-MM-DD | Date not in the ISO format | Read as MM/DD/YYYY; no value has a first part above 12 (D-03) | 551 | 1,023,917.36 |
| A05 | of which also readable as a different valid date in DD/MM/YYYY | Both readings valid and different | Read as MM/DD/YYYY on the evidence of the whole column (D-03) | 181 | 315,045.84 |
| A06 | Branch typed 14 ways (case, spaces, full names) | Raw value differs from its branch code | Explicit mapping table; an unmapped value fails the build (D-04) | 5,676 | 9,991,739.10 |
| A07 | Account with a leading space or a trailing ".0" | Raw value differs from the integer account | Trimmed and read as an integer; an unknown account fails the build (D-09) | 1,434 | 2,551,804.49 |
| B01 | Subtotal rows mixed in with journal lines | JournalID "SUBTOTAL" | Excluded; each subtotal must equal its account-month journal lines (D-06) | 31 | 2,182,617.33 + CAD 359,401.75 |
| B02 | Amounts stored as text with a thousands separator | Separator present in the amount | Read as numbers (D-06) | 18 | 37,724.23 |
| B03 | Amounts with binary floating-point tails | More than two decimals | Rounded to cents; a check bounds the change (D-07) | 29 | 72,727.29 + CAD 70,333.51 |
| B04 | Posting dates stored as DD/MM/YYYY text | All journal lines | Read as DD/MM/YYYY (D-03) | 1,473 | 2,182,617.33 + CAD 359,401.75 |
| B05 | of which also readable as a different valid date in MM/DD/YYYY | Both readings valid and different | Read as DD/MM/YYYY on the evidence of the whole column (D-03) | 531 | 753,324.79 + CAD 175,503.87 |
| B07 | Account 7335-RM-HYD (73xx-RM range) missing from Accounting's account map | Kept account not found in the map | Included as R&M (README rule 6, D-05); Accounting to complete the map | 23 | 78,112.46 |

**README rules applied**

| ID | Issue | Detection | Rule applied | Rows | USD |
|---|---|---|---|---:|---:|
| A03 | Lines dated outside Q3 | Transaction date outside the quarter | Excluded (README rule 3) | 1,422 | 2,570,999.19 |
| B06 | Lakeshore lines posted outside Q3 | Posting date outside the quarter | Excluded (README rule 3) | 152 | – (CAD 359,401.75) |
| A09 | Capitalised rebuild operations (75, 100) on R&M accounts | Operation in the capitalised list | Excluded from R&M (README rule 2) | 174 | 409,398.55 |
| A08 | Elmwood activity dated on or after 1 August | Closed branch, date on or after the close | Reported under Oakdale (README rule 4) | 126 | 265,830.48 |
| A10 | Reversals (negative quantity), each on its own line number | Quantity below zero | Counted in the month of its own date (README rule 3) | 60 | -156,212.59 |
| B08 | Lakeshore credit lines | Amount below zero | Counted in the month of its own date (README rule 3) | 25 | -45,217.76 |
| A11 | Customer number on R&M-account lines | Customer number present | No change: the account decides (README rule 1) | 3,480 | 7,670,610.69 |

**Controls with no exceptions:**
- A12: ExtCost equals Qty × UnitCost on every line.
- B09: no JournalID is used twice.

## Part 3 · Reconciliation to Accounting

| Step | Item | Branch | Month | USD | Running total |
|---:|---|---|---|---:|---:|
| 0 | Finance R&M | | | 14,090,228.96 | 14,090,228.96 |
| 1 | R1 · JE-0931 accrual | RIV | 2026-09 | +18,450.00 | 14,108,678.96 |
| 2 | R2 · Lakeshore September at the month-end rate | LKS | 2026-09 | +11,681.61 | 14,120,360.57 |
| | Accounting as reported | | | 14,120,360.57 | |
| | **Residual** | | | **0.00** | |

**R1 · JE-0931 accrual (+18,450.00)**
- **Evidence:** a manual entry in Accounting's September close register: RIV, account 6150, "Accrual – outside hydraulic cylinder repair, invoice pending". It was posted on 30 September at 22:14, after the last ERP-A export of the quarter (18:00). No ERP-A line in any export carries this amount.
- **Who is right:** both, under their own definitions. Finance's R&M excludes manual journal entries (README rule 7). Accounting is right to accrue a September service whose invoice has not yet arrived.
- **What should change:** neither total. Accounting reverses the accrual in October when the invoice posts in ERP-A, so that the cost is not counted twice in Q4.

**R2 · Lakeshore September at the month-end rate (+11,681.61)**
- **Evidence:** Lakeshore's September R&M is CAD 667,520.79.
  - At the September average rate (0.7210) it is USD 481,282.49, which is Finance's figure.
  - At the month-end rate (0.7385) it is USD 492,964.10.
  - July and August must be at the average rate for the bridge to close.
- **Who is right:** Finance. README rule 5 translates Lakeshore at the monthly average rate.
- **What should change:** Accounting posts a correcting entry to Lakeshore's September translation at the average rate.
  - **If September is still open:** post it in September, which reduces Q3 R&M to USD 14,108,678.96.
  - **If September is closed:** post it in October as a prior-period correction, disclosed against Q3.
  - **To prevent a recurrence:** keep one governed rate table, with the rate type per use.

**Tested and ruled out.** The search covered:
- each manual journal entry, in or out;
- average or month-end rates for each month, and three whole-quarter rate methods;
- Accounting's account map in place of the 73xx-RM rule;
- each data quality treatment reversed.

Only the combination above closes. The nearest alternatives miss by USD 0.04 and require eleven simultaneous deviations.
- **JE-0940** (posted 2 October) is in neither total.
- **7335-RM-HYD** is in Accounting's total despite its absence from the map. It is not a reconciling item but a latent risk for any build that classifies Lakeshore accounts through the map (Part 2, B07).

The full bridge and its evidence are in [docs/bridge.md](docs/bridge.md) and [output/bridge.csv](output/bridge.csv). The search is in [analysis/scenarios.py](analysis/scenarios.py).

## Part 4 · Design memo: automating group R&M reporting

**Scope:** 6 legal entities, 4 ERPs and a few tens of thousands of transaction rows per week. The volume is small; the challenge is one Finance-owned definition of R&M across every entity.

### 1. Getting the data out
- **Main ERP:** never queried live. Extraction runs against a reporting copy that IT restores from the nightly backup.
- **Other ERPs:** a read replica, an API or scheduled file exports, as each supports.
- **Landing:** raw and untouched, with load metadata (source, extract time, file hash).

### 2. Platform: Microsoft Fabric
- **Why Fabric:** Northline already runs on Microsoft 365 and Power BI. Fabric shares their identity, security and billing, and its semantic model serves Power BI and AI tools alike. Databricks or Snowflake would add a second platform that this volume does not need.
- **Cost:** F2, ~USD 260/month pay-as-you-go or ~USD 160 on a 1-year reservation; F4 (~USD 525 / ~315) if AI workloads need headroom. Storage is negligible. Below F64, viewers need Power BI Pro (~USD 14/user/month), often already in M365 plans.

### 3. Where the Finance rules live, and who owns them
- **Rules as code:** the R&M definition (accounts, capex operations, branch remaps, FX policy, rounding) lives in a versioned rules file in Git, as in this take-home (`config/rules.toml`). Finance owns the content and approves changes by pull request; the data team is the custodian.
- **Governed reference data:** account maps, FX rates (with the rate type per use) and branch maps, each with an owner and a completeness check that fails the load. Lakeshore account 7335-RM-HYD, missing from Accounting's map, shows why: a map-driven build would silently drop USD 78k of R&M.
- **One semantic model** holds the governed R&M definition; Power BI and AI tools query it, never raw tables.
- **Manual journal entries:** one agreed definition, with both views as named measures ("R&M per ERP", "R&M incl. manual JEs"), so the difference is visible by design.

### 4. First 30 days

| Week | Deliverables |
|---|---|
| 1 | Access requests for all 4 ERPs on day 1 (the longest lead time); backup restore agreed with IT; Fabric workspaces. |
| 2 | Main ERP and Lakeshore landing daily; R&M logic ported, rules file signed off by Finance. |
| 3 | Remaining ERPs landing and profiled; semantic model, Power BI report, automated bridge to Accounting. |
| 4 | Data quality alerts to owners; remaining account maps in review; AI pilot with one Finance user. |

**Day-30 outcome:** all 4 ERPs land daily, raw and profiled. R&M is automated, reconciled to the close and published for the main ERP and Lakeshore; the other entities have issues logged, treatments in review and a dated go-live. Confidence comes from profiling and sign-off: profiling two sources here identified ten data issues (Part 2).

**Main risk:** access and sign-off, not build time, which is why those requests are issued on day 1.

## Part 5 · How I used AI

### Tools and roles

I worked in two tiers:

| Tool | Role |
|---|---|
| Claude chat (Opus 5.5, medium effort) | Planning and review partner: strategy, interpreting findings, designing the verification, drafting instructions for Claude Code, and reviewing its output. |
| Claude Code (Opus 5.5, extra-high effort) | Profiling, the pipeline build, the bridge search and the sensitivity analysis. |
| Claude Code (Sonnet 5.5, medium effort) | The independent verification build. A different model was used on purpose, to reduce correlated errors. |

I acted as the link between the two tiers: I decided every data treatment, edited the instructions and reviewed both tools' output critically. A `CLAUDE.md` in the repo set the agent's guardrails:
- Work stage by stage, and stop after each stage.
- No rule values in code.
- Propose decisions and wait for confirmation.
- Log corrections.

The full running log is in `docs/ai_log.md`.

### Most useful instructions

The instructions were drafted in the planning chat and refined by me.

1. **Profiling, stage-gated:** "This is the profiling stage only: no transforms, no pipeline, no config. Report every anomaly with evidence. Do not decide treatments; flag anything where the README rule is ambiguous. Stop after that." This kept every judgment call with me. Every treatment in `docs/decisions.md` is a confirmed human decision.
2. **Code-blind verification:** a fresh session on a different model was given only the raw ERP files, the README and `decisions.md`. It got no code, config or outputs, and no Accounting files, so that it could not steer toward the expected total. Instruction: "Write a single independent script… use exact decimal arithmetic for money."
3. **Bridge:** "Explicitly check for alternative combinations that also close, not just the first one that does." This established the bridge as the unique solution rather than merely a plausible one.

### What the AI got wrong, and how I caught it

Nine entries are in the full log. The most instructive:

- **A silent data loss (Claude Code).** It parsed Lakeshore amounts with a lenient cast. 18 text amounts with thousands separators (CAD 51,965.23) would have become NULL and silently dropped out of R&M. A strict typed read failed on one cell and exposed it, and the subtotal tie-out confirmed the fix.
- **Verification design (planning chat).** It first proposed a fully blind rebuild. I asked what a match or mismatch would actually prove: any difference would mix implementation bugs with judgment calls I had already made deliberately. It was redesigned as code-blind, so that any difference would point to an implementation bug.
- **A wrong prediction (planning chat).** It expected account 7335-RM-HYD, which is missing from Accounting's map, to be a reconciling item. The exhaustive bridge search disproved this: Accounting's total already includes it. The finding was reframed as a latent governance risk.
- **A check that could not fail properly (Claude Code).** A deliberate failure test showed the bridge crashing instead of failing its residual check. It was fixed and retested, since a check can only be relied on once it has been seen to fail.
- **Rules duplicated in agent instructions (planning chat).** It proposed putting the Finance rules in both `CLAUDE.md` and config. Now config is the single source of truth.

### How the output was checked
- 27 build checks:
  - row and amount conservation per source
  - format checks on the output file as written
  - bridge residual exactly 0.00
  - no plug items
- Failure-path test: removing one branch mapping made the build fail loudly and name the value.
- Reruns are byte-identical. A search confirmed no rule values are hardcoded.
- **Independent build: all 13 cells match to the cent** (USD 14,090,228.96).
- Bridge uniqueness: exactly one combination closes out of about 78 million evaluated.
- Line-by-line human review of every stage's output.

### How much of the code was AI-written

**Approximately 95% or more.** My contribution was:
- the specification and stage design
- every treatment decision
- the verification design
- review

Where the AI was wrong, I corrected it by changing the instruction or the rule, not by hand-editing code. The SQL is deliberately short and readable, with one pipeline step per file, so that I can explain and change it live.
