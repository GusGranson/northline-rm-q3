-- =============================================================================
-- Profile: data/raw/accounting_je_register_sep_close.csv
-- Manual journal entries posted by Accounting during the September close.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/accounting_je_register_sep_close/NN_<name>.csv.
-- Runner variables: q_start, q_end, last_export_at.
-- ERP-A, ERP-B and the account map are loaded only to look up whether a JE's
-- account and amount also appear in the ERP data.
-- =============================================================================

INSTALL excel;
LOAD excel;

CREATE TABLE je_raw AS
SELECT *
FROM read_csv('data/raw/accounting_je_register_sep_close.csv', header = true, all_varchar = true);

CREATE TABLE account_map_raw AS
SELECT *
FROM read_csv('data/raw/account_map_lakeshore.csv', header = true, all_varchar = true);

CREATE TABLE erp_a_raw AS
SELECT *
FROM read_csv('data/raw/erp_a_sro_transactions.csv', header = true, all_varchar = true);

CREATE TABLE erp_b_raw AS
SELECT *
FROM read_xlsx('data/raw/erp_b_lakeshore_gl_detail.xlsx',
               header = true, all_varchar = true, stop_at_empty = false);

CREATE VIEW je AS
SELECT
    rowid + 2                              AS file_line,
    *,
    TRY_CAST(PostedAt AS TIMESTAMP)        AS posted_at_p,
    TRY_CAST(Amount AS DECIMAL(18, 2))     AS amount_n
FROM je_raw;

-- Same measurement lenses as the per-source profiles (see those files).
CREATE VIEW erp_a AS
SELECT
    rowid + 2 AS file_line, *,
    CASE
        WHEN TransDate LIKE '____-__-__' THEN TRY_STRPTIME(TransDate, '%Y-%m-%d')
        WHEN TransDate LIKE '__/__/____' THEN TRY_STRPTIME(TransDate, '%m/%d/%Y')
    END::DATE                                                   AS trans_date_p,
    left(upper(trim(Whse)), 3)                                  AS whse_prefix3,
    TRY_CAST(TRY_CAST(trim(Acct) AS DECIMAL(10, 1)) AS INTEGER) AS acct_n,
    TRY_CAST(ExtCost AS DECIMAL(18, 2))                         AS ext_cost_n
FROM erp_a_raw;

CREATE VIEW erp_b AS
SELECT
    rowid + 2 AS excel_row, *,
    TRY_STRPTIME(PostingDate, '%d/%m/%Y')::DATE                 AS posting_date_p,
    TRY_CAST(replace(AmountCAD, ',', '') AS DECIMAL(18, 2))     AS amount_cad_n
FROM erp_b_raw
WHERE regexp_full_match(JournalID, 'LK[0-9]+');


-- name: column_types_inferred
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_csv('data/raw/accounting_je_register_sep_close.csv'));

-- name: contents
-- Every JE with timing facts and what the account is in the reference data.
SELECT
    je.file_line,
    je.JE_ID,
    je.PostedAt,
    strftime(je.posted_at_p, '%A')                               AS posted_weekday,
    je.posted_at_p > getvariable('q_end') + INTERVAL 1 DAY       AS posted_after_q3_end,
    je.posted_at_p > getvariable('last_export_at')               AS posted_after_readme_last_export,
    je.Entity,
    je.Branch,
    je.Account,
    je.Amount,
    je.Description,
    m.LocalAccount IS NOT NULL                                   AS account_is_lks_local,
    m.GroupAccount                                               AS lks_map_group_account,
    m.GroupDescription                                           AS lks_map_group_description,
    je.Account IN (SELECT DISTINCT acct_n::VARCHAR FROM erp_a)   AS account_seen_in_erp_a
FROM je
LEFT JOIN account_map_raw AS m ON m.LocalAccount = je.Account
ORDER BY je.file_line;

-- name: totals_by_account
-- Totals per entity only: the CA entry is in CAD, the US entries in USD, so
-- there is no all-entity total.
SELECT Entity, coalesce(Account, '(entity total)') AS Account, count(*) AS entries, sum(amount_n) AS amount
FROM je
GROUP BY GROUPING SETS ((Entity, Account), (Entity))
ORDER BY Entity, Account;

-- name: amount_matches_erp_a
-- ERP-A lines (any date) whose ExtCost equals a JE amount in absolute value.
SELECT
    je.JE_ID, je.Branch AS je_branch, je.Account AS je_account, je.Amount AS je_amount,
    a.file_line, a.SRO, a.Line, a.Oper, a.Whse, a.TransDate, a.Acct, a.Item, a.ExtCost, a.ExportedAt
FROM je
JOIN erp_a AS a ON abs(a.ext_cost_n) = abs(je.amount_n)
ORDER BY je.JE_ID, a.file_line;

-- name: amount_matches_erp_b
-- ERP-B journal lines (any date) whose AmountCAD equals a JE amount in absolute value.
SELECT
    je.JE_ID, je.Branch AS je_branch, je.Account AS je_account, je.Amount AS je_amount,
    b.excel_row, b.JournalID, b.PostingDate, b.LocalAccount, b.AmountCAD
FROM je
JOIN erp_b AS b ON abs(b.amount_cad_n) = abs(je.amount_n)
ORDER BY je.JE_ID, b.excel_row;

-- name: erp_a_same_branch_account_late_sep
-- For US JEs: ERP-A activity on the same branch prefix and account in the last
-- week of September and after, by export. Context for accruals and credits.
SELECT
    je.JE_ID, je.Branch, je.Account, je.Amount,
    a.ExportedAt,
    count(*)            AS erp_a_lines,
    sum(a.ext_cost_n)   AS erp_a_usd,
    min(a.trans_date_p) AS min_trans_date,
    max(a.trans_date_p) AS max_trans_date
FROM je
JOIN erp_a AS a
  ON a.whse_prefix3 = je.Branch
 AND a.acct_n::VARCHAR = je.Account
 AND a.trans_date_p >= getvariable('q_end') - 6
WHERE je.Entity = 'US'
GROUP BY ALL
ORDER BY je.JE_ID, a.ExportedAt;
