-- =============================================================================
-- 06 · Q3 R&M in USD by branch and month (the Part 1 output)
--   ERP-A: kept USD lines summed by reporting branch and month.
--   ERP-B: kept CAD lines summed by month, then each month's total times that
--          month's rate, rounded to cents (README rule 5, D-07).
--   Every total is rounded at branch-month level (README rule 8).
-- No zero rows are added: a branch-month with no kept lines is absent (D-12).
-- =============================================================================

CREATE TABLE lks_month_cad AS
SELECT
    report_branch       AS branch,
    period_month        AS month,
    sum(amount_cad)     AS cad
FROM erp_b_lines
WHERE bucket = 'kept'
GROUP BY ALL;

CREATE TABLE rm_by_branch AS
SELECT
    report_branch                                              AS branch,
    period_month                                               AS month,
    round(sum(ext_cost_usd), getvariable('rounding_decimals')) AS rm_usd
FROM erp_a_lines
WHERE bucket = 'kept'
GROUP BY ALL
UNION ALL
SELECT
    l.branch,
    l.month,
    round(l.cad * fx.rate, getvariable('rounding_decimals'))   AS rm_usd
FROM lks_month_cad AS l
LEFT JOIN stg_fx AS fx USING (month);

-- The file exactly as it is written: text columns, so the format checks in
-- 90_checks.sql test the same strings that land in the CSV.
CREATE TABLE rm_q3_by_branch AS
SELECT
    branch                     AS Branch,
    month                      AS Month,
    CAST(rm_usd AS VARCHAR)    AS RM_USD
FROM rm_by_branch
ORDER BY list_position(getvariable('branches_codes'), branch), month;
