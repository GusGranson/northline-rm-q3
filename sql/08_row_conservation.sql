-- =============================================================================
-- 08 · Row conservation and line-level audit trail
-- row_conservation: raw rows and amount per source, then each bucket (D-10).
--   Check C18/C19 requires raw = sum of buckets, in rows and in amount.
-- line_buckets: every raw row of both ERPs with its bucket and reporting
--   branch-month, so any output figure can be traced to source lines.
-- =============================================================================

CREATE TABLE row_conservation AS
SELECT * FROM (
SELECT 'ERP-A' AS source, 'raw' AS bucket, count(*) AS rows,
       sum(TRY_CAST(ExtCost AS DECIMAL(18, 2))) AS amount_native, getvariable('erp_a_currency') AS currency
FROM raw_erp_a
UNION ALL
SELECT 'ERP-A', bucket, count(*), sum(ext_cost_usd), getvariable('erp_a_currency')
FROM erp_a_lines
GROUP BY bucket
UNION ALL
SELECT 'ERP-B', 'raw', count(*),
       sum(TRY_CAST(replace(AmountCAD, getvariable('erp_b_thousands_separator'), '') AS DECIMAL(18, 2))),
       getvariable('erp_b_currency')
FROM raw_erp_b
UNION ALL
SELECT 'ERP-B', bucket, count(*), sum(amount_cad), getvariable('erp_b_currency')
FROM erp_b_lines
GROUP BY bucket
)
ORDER BY source, CASE bucket WHEN 'raw' THEN 0 WHEN 'kept' THEN 2 ELSE 1 END, bucket;

CREATE TABLE line_buckets AS
SELECT
    'ERP-A'              AS source,
    source_row,
    line_key             AS record_key,
    exported_at,
    bucket,
    branch,
    report_branch,
    period_month,
    ext_cost_usd         AS amount_native,
    getvariable('erp_a_currency') AS currency
FROM erp_a_lines
UNION ALL
SELECT
    'ERP-B',
    source_row,
    journal_id,
    NULL,
    bucket,
    branch,
    report_branch,
    period_month,
    amount_cad,
    getvariable('erp_b_currency')
FROM erp_b_lines
ORDER BY source, source_row;
