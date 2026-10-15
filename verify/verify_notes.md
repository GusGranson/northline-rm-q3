# verify_notes.md — Q3 2026 R&M build

Script: `build_rm_q3.py` (run `python -I build_rm_q3.py [data_dir]`) -> `rm_q3_by_branch.csv`. Decimal arithmetic only.

## Applied
README rules 1-8 and decisions D-01..D-12 as written (dedupe SRO+Line latest ExportedAt; explicit Whse map; Acct trimmed/`.0` stripped; opers 75/100 excluded; ELM from 1-Aug -> OAK; Lakeshore 73xx-RM pattern incl. 7335-RM-HYD; SUBTOTAL rows dropped and used as a control; text amounts parsed; monthly CAD total x avg rate, half-up to cents; no ELM rows after July, 13 rows).
Built-in checks (script aborts on failure): unmapped Whse, non-group Acct, unparsable dates, non-LK journal IDs, SUBTOTAL != journal lines per account/month, Q3 line seen in an export after 2026-09-30 18:00.

## Not covered by README/decisions — my calls
1. `accounting_close_summary.csv` and `accounting_je_register_sep_close.csv` are listed in the README but absent from the folder. Per rule 7 they are not inputs; no bridge/reconciliation to Accounting was done (D-08 stays deferred).
2. ERP-A ExtCost is used as given (not recomputed from Qty x UnitCost); reversals are taken at their posted ExtCost sign. Sign consistency was spot-checked (see run output in the session).
3. 7335-RM-HYD is matched by pattern `73\d\d-RM(-...)?` (rule 6 / D-05); it has no group account.
4. ERP-B float noise: amounts converted via repr() then quantized to cents (D-07's <0.000001 tolerance not separately asserted; repr of the float is the shortest round-trip text).
5. Outputs sorted by branch (RIV, OAK, PIN, ELM, LKS) then month. Month format YYYY-MM.
6. Dedupe applied before the period filter, with the D-10 bucket order; no DQ log file produced (not requested).
