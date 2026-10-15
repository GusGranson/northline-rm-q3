-- =============================================================================
-- 09 · Bridge: Finance R&M to Accounting's reported total (Part 3)
-- Every reconciling item is computed from a source record; nothing is set to
-- the residual (no plugs). Check C25 requires the residual to be exactly 0.00.
--   JE  manual journal entries on R&M accounts posted by the period end: in
--       Accounting's total, not in Finance's (README rule 7)
--   FX  Lakeshore months Accounting translated at another rate than README
--       rule 5's, per [bridge] accounting_fx in config/pipeline.toml
-- Accounting's file and the JE register are read here only; they are not
-- inputs to Finance's R&M.
-- =============================================================================

CREATE TABLE stg_accounting_close AS
SELECT
    Period                              AS period,
    Metric                              AS metric,
    TRY_CAST(USD AS DECIMAL(18, 2))     AS usd
FROM read_csv(getvariable('sources_accounting_close'), header = true, all_varchar = true);

CREATE TABLE stg_je AS
SELECT
    JE_ID                               AS je_id,
    TRY_CAST(PostedAt AS TIMESTAMP)     AS posted_at,
    Entity                              AS entity,
    Branch                              AS branch,
    Account                             AS account,
    TRY_CAST(Amount AS DECIMAL(18, 2))  AS amount,
    Description                         AS description,
    -- R&M by the build's own rules: a group R&M account (README rule 1) or a
    -- Lakeshore local account in the 73xx-RM range (rule 6, booked in CAD).
    list_contains(getvariable('rm_group_accounts'), TRY_CAST(Account AS INTEGER)) IS TRUE AS is_rm_group_account,
    regexp_matches(Account, getvariable('erp_b_rm_local_account_pattern'))        AS is_rm_local_account
FROM read_csv(getvariable('sources_je_register'), header = true, all_varchar = true);

-- No [[bridge.accounting_fx]] entry in config means Accounting used Finance's
-- rate in every month; run.py then creates no table, so start from an empty one.
CREATE TABLE IF NOT EXISTS cfg_bridge_accounting_fx (month VARCHAR, rate_column VARCHAR);

-- Every rate in the FX file, and the rate Accounting used per month: its
-- override from config where the bridge found one, otherwise Finance's rate.
CREATE TABLE fx_all AS
SELECT Month AS month, rate_column, TRY_CAST(rate_raw AS DECIMAL(18, 8)) AS rate
FROM raw_fx
UNPIVOT (rate_raw FOR rate_column IN (COLUMNS(* EXCLUDE (Month))));

CREATE TABLE accounting_fx AS
SELECT
    f.month,
    coalesce(o.rate_column, getvariable('fx_rate_column')) AS rate_column,
    a.rate
FROM stg_fx AS f
LEFT JOIN cfg_bridge_accounting_fx AS o USING (month)
LEFT JOIN fx_all AS a
       ON a.month = f.month
      AND a.rate_column = coalesce(o.rate_column, getvariable('fx_rate_column'));

CREATE TABLE bridge_items AS
SELECT
    'JE'                                                     AS item_type,
    je.je_id                                                 AS source_ref,
    'Manual JE ' || je.je_id || ' on ' || je.account || ', posted '
        || strftime(je.posted_at, '%Y-%m-%d %H:%M') || ': ' || je.description
        || '. In Accounting''s total; not in Finance''s (README rule 7)' AS description,
    je.branch,
    strftime(je.posted_at, '%Y-%m')                          AS month,
    CASE WHEN je.is_rm_group_account THEN je.amount
         ELSE round(je.amount * afx.rate, getvariable('rounding_decimals'))
    END                                                      AS amount_usd
FROM stg_je AS je
LEFT JOIN accounting_fx AS afx ON afx.month = strftime(je.posted_at, '%Y-%m')
WHERE (je.is_rm_group_account OR je.is_rm_local_account)
  AND je.posted_at::DATE <= getvariable('period_end')
UNION ALL
SELECT
    'FX',
    l.month,
    'Lakeshore ' || l.month || ' R&M (CAD ' || l.cad || ') translated by Accounting at '
        || afx.rate_column || ' ' || afx.rate::DECIMAL(10, 4) || ' instead of '
        || getvariable('fx_rate_column') || ' ' || fx.rate::DECIMAL(10, 4) || ' (README rule 5)',
    l.branch,
    l.month,
    round(l.cad * afx.rate, getvariable('rounding_decimals'))
      - round(l.cad * fx.rate, getvariable('rounding_decimals'))
FROM lks_month_cad AS l
JOIN stg_fx AS fx USING (month)
JOIN accounting_fx AS afx USING (month)
WHERE afx.rate_column <> getvariable('fx_rate_column');

-- Finance total, each item with a running total, Accounting's reported total,
-- and the residual. Accounting's row is the one for this period (e.g. 2026-Q3).
CREATE TABLE bridge AS
WITH finance AS (
    SELECT sum(rm_usd) AS usd FROM rm_by_branch
),
accounting AS (
    SELECT usd FROM stg_accounting_close
    WHERE period = strftime(getvariable('period_start'), '%Y') || '-Q' || quarter(getvariable('period_start'))
),
items AS (
    SELECT row_number() OVER (ORDER BY item_type DESC, source_ref) AS step, *
    FROM bridge_items
)
SELECT 0 AS step, 'finance' AS line_type, 'output/rm_q3_by_branch.csv' AS source_ref,
       'Finance R&M for the period (sum of the Part 1 output)' AS description,
       NULL AS branch, NULL AS month, f.usd AS amount_usd, f.usd AS running_total_usd
FROM finance AS f
UNION ALL
SELECT i.step, 'reconciling_item_' || lower(i.item_type), i.source_ref, i.description, i.branch, i.month,
       i.amount_usd,
       f.usd + sum(i.amount_usd) OVER (ORDER BY i.step)
FROM items AS i, finance AS f
UNION ALL
SELECT (SELECT count(*) FROM items) + 1, 'accounting', 'accounting_close_summary.csv',
       'Accounting R&M as reported in the close', NULL, NULL, a.usd, NULL
FROM accounting AS a
UNION ALL
SELECT (SELECT count(*) FROM items) + 2, 'residual', NULL,
       'Accounting reported minus (Finance + reconciling items); must be 0.00', NULL, NULL,
       a.usd - f.usd - coalesce((SELECT sum(amount_usd) FROM items), 0), NULL
FROM accounting AS a, finance AS f
ORDER BY step;
