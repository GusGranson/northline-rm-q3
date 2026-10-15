-- =============================================================================
-- 01 · Stage ERP-A (SRO transaction lines, USD)
-- Load the export verbatim, then parse every column into a typed column next
-- to its raw text. No row is dropped here; rows that fail to parse are caught
-- by the checks in 90_checks.sql.
--   D-01 line key · D-03 date formats · D-04 Whse map · D-07 DECIMAL · D-09 Acct
-- =============================================================================

CREATE TABLE raw_erp_a AS
SELECT *
FROM read_csv(getvariable('sources_erp_a'), header = true, all_varchar = true);

CREATE TABLE stg_erp_a AS
WITH src AS (
    SELECT
        rowid + 2 AS source_row,   -- line number in the CSV (line 1 is the header)
        -- D-01: the columns named in erp_a_dedupe_key identify a line
        list_value(*COLUMNS(c -> list_contains(getvariable('erp_a_dedupe_key'), c))) AS line_key_parts,
        *
    FROM raw_erp_a
)
SELECT
    s.source_row,
    array_to_string(s.line_key_parts, '|')                               AS line_key,
    len(list_filter(s.line_key_parts, p -> p IS NULL))                   AS line_key_nulls,
    s.SRO                                                                AS sro,
    TRY_CAST(s.Line AS INTEGER)                                          AS line,
    TRY_CAST(s.Oper AS INTEGER)                                          AS oper,
    s.Whse                                                               AS whse_raw,
    m.branch,                                                            -- D-04 (NULL = not in the map)
    s.TransDate                                                          AS trans_date_raw,
    TRY_STRPTIME(s.TransDate, getvariable('erp_a_date_formats'))::DATE   AS trans_date,   -- D-03
    s.TransType                                                          AS trans_type,
    s.Acct                                                               AS acct_raw,
    TRY_CAST(regexp_replace(trim(s.Acct), '\.0$', '') AS INTEGER)        AS acct,         -- D-09
    s.Item                                                               AS item,
    TRY_CAST(s.Qty AS DECIMAL(18, 4))                                    AS qty,
    s.UnitCost                                                           AS unit_cost_raw,
    TRY_CAST(s.UnitCost AS DECIMAL(18, 2))                               AS unit_cost,    -- D-07
    s.ExtCost                                                            AS ext_cost_raw,
    TRY_CAST(s.ExtCost AS DECIMAL(18, 2))                                AS ext_cost_usd, -- D-07
    s.CustNum                                                            AS cust_num,
    TRY_CAST(s.ExportedAt AS TIMESTAMP)                                  AS exported_at
FROM src AS s
LEFT JOIN cfg_erp_a_whse_map AS m ON m.raw = s.Whse;
