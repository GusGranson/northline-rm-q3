-- =============================================================================
-- 05 · Classify ERP-B lines
-- Every staged row gets exactly one bucket (D-10), tested in this order:
--   subtotal_row     D-06: SUBTOTAL rows are not postings (kept as a control in 90_checks.sql)
--   outside_period   README rule 3: PostingDate outside Q3
--   not_rm_account   README rule 6: local account outside the 73xx-RM range (D-05)
--   kept             R&M for the output
-- =============================================================================

CREATE TABLE erp_b_lines AS
SELECT
    *,
    CASE
        WHEN row_type = 'subtotal'
            THEN 'subtotal_row'
        WHEN posting_date NOT BETWEEN getvariable('period_start') AND getvariable('period_end')
            THEN 'outside_period'
        WHEN NOT is_rm_local_account
            THEN 'not_rm_account'
        ELSE 'kept'
    END                                  AS bucket,
    branch                               AS report_branch,
    strftime(posting_date, '%Y-%m')      AS period_month
FROM stg_erp_b;
