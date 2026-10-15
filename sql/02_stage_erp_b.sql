-- =============================================================================
-- 02 · Stage ERP-B (Lakeshore GL detail, CAD)
-- Load the sheet verbatim, then parse it. Every row is kept and typed as a
-- journal line or a subtotal; anything else is caught by 90_checks.sql.
--   D-03 date format · D-05 R&M range · D-06 subtotals, text amounts · D-07 DECIMAL
-- =============================================================================

INSTALL excel;
LOAD excel;

CREATE TABLE raw_erp_b AS
SELECT *
FROM read_xlsx(getvariable('sources_erp_b'), header = true, all_varchar = true, stop_at_empty = false);

CREATE TABLE stg_erp_b AS
SELECT
    rowid + 2                                                              AS source_row,  -- sheet row (row 1 is the header)
    JournalID                                                              AS journal_id,
    CASE
        WHEN JournalID = getvariable('erp_b_subtotal_marker')                       THEN 'subtotal'
        WHEN regexp_matches(JournalID, getvariable('erp_b_journal_id_pattern'))     THEN 'journal'
    END                                                                    AS row_type,    -- D-06 (NULL = unrecognised)
    PostingDate                                                            AS posting_date_raw,
    TRY_STRPTIME(PostingDate, getvariable('erp_b_date_formats'))::DATE     AS posting_date, -- D-03
    LocalAccount                                                           AS local_account,
    Description                                                            AS description,
    AmountCAD                                                              AS amount_raw,
    -- D-06: amounts typed as text carry a thousands separator; strip it. D-07: cents.
    TRY_CAST(replace(AmountCAD, getvariable('erp_b_thousands_separator'), '') AS DECIMAL(18, 2)) AS amount_cad,
    Source                                                                 AS source,
    regexp_matches(LocalAccount, getvariable('erp_b_rm_local_account_pattern')) AS is_rm_local_account, -- README rule 6, D-05
    getvariable('erp_b_branch')                                            AS branch
FROM raw_erp_b;
