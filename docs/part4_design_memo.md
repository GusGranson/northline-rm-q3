# Design memo: automating group R&M reporting

**Scope:** 6 legal entities, 4 ERPs and a few tens of thousands of transaction rows per week. The volume is small; the challenge is one Finance-owned definition of R&M across every entity.

## 1. Getting the data out
- **Main ERP:** never queried live. Extraction runs against a reporting copy that IT restores from the nightly backup.
- **Other ERPs:** a read replica, an API or scheduled file exports, as each supports.
- **Landing:** raw and untouched, with load metadata (source, extract time, file hash).

## 2. Platform: Microsoft Fabric
- **Why Fabric:** Northline already runs on Microsoft 365 and Power BI. Fabric shares their identity, security and billing, and its semantic model serves Power BI and AI tools alike. Databricks or Snowflake would add a second platform that this volume does not need.
- **Cost:** F2, ~USD 260/month pay-as-you-go or ~USD 160 on a 1-year reservation; F4 (~USD 525 / ~315) if AI workloads need headroom. Storage is negligible. Below F64, viewers need Power BI Pro (~USD 14/user/month), often already in M365 plans.

## 3. Where the Finance rules live, and who owns them
- **Rules as code:** the R&M definition (accounts, capex operations, branch remaps, FX policy, rounding) lives in a versioned rules file in Git, as in this take-home (`config/rules.toml`). Finance owns the content and approves changes by pull request; the data team is the custodian.
- **Governed reference data:** account maps, FX rates (with the rate type per use) and branch maps, each with an owner and a completeness check that fails the load. Lakeshore account 7335-RM-HYD, missing from Accounting's map, shows why: a map-driven build would silently drop USD 78k of R&M.
- **One semantic model** holds the governed R&M definition; Power BI and AI tools query it, never raw tables.
- **Manual journal entries:** one agreed definition, with both views as named measures ("R&M per ERP", "R&M incl. manual JEs"), so the difference is visible by design.

## 4. First 30 days

| Week | Deliverables |
|---|---|
| 1 | Access requests for all 4 ERPs on day 1 (the longest lead time); backup restore agreed with IT; Fabric workspaces. |
| 2 | Main ERP and Lakeshore landing daily; R&M logic ported, rules file signed off by Finance. |
| 3 | Remaining ERPs landing and profiled; semantic model, Power BI report, automated bridge to Accounting. |
| 4 | Data quality alerts to owners; remaining account maps in review; AI pilot with one Finance user. |

**Day-30 outcome:** all 4 ERPs land daily, raw and profiled. R&M is automated, reconciled to the close and published for the main ERP and Lakeshore; the other entities have issues logged, treatments in review and a dated go-live. Confidence comes from profiling and sign-off: profiling two sources here identified ten data issues (Part 2).

**Main risk:** access and sign-off, not build time, which is why those requests are issued on day 1.
