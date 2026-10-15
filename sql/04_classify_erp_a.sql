-- =============================================================================
-- 04 · Classify ERP-A lines
-- Every staged row gets exactly one bucket (D-10), tested in this order:
--   duplicate_copy         D-01: same line key in an earlier/later export; keep one copy
--   outside_period         README rule 3: TransDate outside Q3 (D-02: ExportedAt is not a filter)
--   not_rm_account         README rule 1: Acct not an R&M group account
--   capitalised_operation  README rule 2: SRO operation is a capitalised rebuild
--   kept                   R&M for the output
-- report_branch applies README rule 4 (closed branch -> receiving branch).
-- =============================================================================

CREATE TABLE erp_a_lines AS
WITH ranked AS (
    SELECT
        *,
        row_number() OVER (
            PARTITION BY line_key
            ORDER BY
                CASE WHEN getvariable('erp_a_dedupe_keep') = 'latest'   THEN exported_at END DESC,
                CASE WHEN getvariable('erp_a_dedupe_keep') = 'earliest' THEN exported_at END ASC,
                source_row DESC
        ) AS copy_rank  -- 1 = the copy D-01 keeps
    FROM stg_erp_a
)
SELECT
    r.*,
    CASE
        WHEN r.copy_rank > 1
            THEN 'duplicate_copy'
        WHEN r.trans_date NOT BETWEEN getvariable('period_start') AND getvariable('period_end')
            THEN 'outside_period'
        WHEN NOT list_contains(getvariable('rm_group_accounts'), r.acct)
            THEN 'not_rm_account'
        WHEN list_contains(getvariable('rm_capitalised_operations'), r.oper)
            THEN 'capitalised_operation'
        ELSE 'kept'
    END                                       AS bucket,
    coalesce(ra.to_branch, r.branch)          AS report_branch,
    strftime(r.trans_date, '%Y-%m')           AS period_month
FROM ranked AS r
LEFT JOIN cfg_branches_reassign AS ra
       ON ra.from_branch = r.branch
      AND r.trans_date >= ra.effective_from;
