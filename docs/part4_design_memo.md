# Design memo: automating group R&M reporting

**Scope:** 6 legal entities, 4 ERPs, a few tens of thousands of transaction rows per week. This is a small data volume. The main challenge is not compute capacity but bringing every entity's numbers under one governed definition owned by Finance.

## 1. Getting the data out
- **Main ERP:** no live queries during business hours. IT restores the nightly backup to a reporting copy, and we extract from that copy. Production is never touched, and the data is as of the nightly close.
- **Other ERPs:** use whatever each one supports cleanly: a read replica, an API, or scheduled file exports to a landing folder.
- **Landing:** every load goes in raw and untouched, with load metadata (source, extract time, file hash).
- **Lessons from this exercise, built in from day one:**
  - Each source gets an explicit snapshot key and dedupe rule. Without it, ERP-A's re-pulled export would have added about USD 1M to R&M.
  - Each source gets explicit date formats per system. ERP-A and ERP-B use opposite conventions.

## 2. Platform: Microsoft Fabric
- **Why Fabric:** Northline already runs on Microsoft 365 and Power BI. Fabric uses the same identity (Entra ID), the same security model and the same bill. Its semantic model is the native layer for both Power BI and AI tools.
- **Alternatives considered:** Databricks or Snowflake are viable, but each adds a second platform, identity model and cost line for a volume that does not require them.
- **Rough monthly cost:**

| Item | Pay-as-you-go | 1-year reservation |
|---|---|---|
| F2 capacity (enough for this volume) | ~USD 260 | ~USD 160 |
| F4 capacity (headroom for AI workloads) | ~USD 525 | ~USD 315 |
| OneLake storage | under USD 5 | under USD 5 |

- **Power BI viewers:** below F64, viewers need Power BI Pro (~USD 14/user/month). Many M365 plans already include it.
- **Sizing:** confirm the SKU from capacity metrics in month one. Start pay-as-you-go and move to a reservation once usage is known.

## 3. Where the Finance rules live, and who owns them
- **R&M definition.** The rules (accounts in scope, capex operations, branch remaps, FX policy, rounding) live as a versioned rules file in Git, separate from pipeline code. This is how the take-home is built (`config/rules.toml`).
  - **Finance (Controller) owns the content.** Changes go through a reviewed pull request that Finance approves.
  - **The data team owns the code and runs it.**
- **Reference data as governed tables, each with a named owner and a completeness check:**
  - account maps per entity
  - the FX rate table, with the rate type per use (P&L at average, balance sheet at month-end)
  - branch and entity maps
- **Why the completeness checks matter:** this exercise found Lakeshore account 7335-RM-HYD missing from Accounting's map. Accounting's current close includes it regardless. An automated build classifying through that map would silently drop USD 78k of R&M.
- **Checks fail the load instead of publishing a wrong number.**
- **One semantic model holds the governed definition of R&M.** Power BI reports and AI tools both query that model, never raw tables. AI answers therefore draw on the same figures that Finance approves.
- **Manual journal entries:** Finance and Accounting agree one definition. Expose both views as named measures ("R&M per ERP" and "R&M incl. manual JEs"), so the gap is visible by design rather than discovered at close.

## 4. First 30 days

| Week | Deliverables |
|---|---|
| 1 | Access requests for all 4 ERPs are issued on day 1 (the longest lead-time item). Backup-restore path agreed with IT. Fabric capacity and dev/prod workspaces with Git integration. Inventory of each ERP: owner, extract option, chart-of-accounts mapping status. |
| 2 | Main ERP and Lakeshore landing raw daily. This exercise's R&M logic ported as the first model, with the rules file signed off by Finance. |
| 3 | The remaining 2 ERPs landing raw and profiled, with data quality issues logged per source. R&M semantic model and Power BI report. The Finance-to-Accounting bridge automated as a recurring reconciliation. |
| 4 | Data quality checks alerting owners. Account maps and treatment decisions for the remaining entities drafted with their accountants. A pilot of AI questions on the semantic model with one Finance user. |

**Day-30 outcome:** all 4 ERPs land daily, raw and profiled. Group R&M is automated, reconciled to the close and published for the entities on the main ERP and Lakeshore. The remaining entities have their data quality issues logged, their treatments in review and a dated go-live. Landing data is quick; establishing confidence in it requires profiling and sign-off. In this exercise, profiling of two sources identified ten data issues (listed in Part 2).

**Main risk:** access and sign-off, not build time. Extract access and map approval depend on IT and each entity's accounting, which is why those requests are issued on day 1.
