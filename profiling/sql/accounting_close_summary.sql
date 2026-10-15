-- =============================================================================
-- Profile: data/raw/accounting_close_summary.csv
-- Total Q3 R&M as reported by Accounting in the close.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/accounting_close_summary/NN_<name>.csv.
-- =============================================================================

CREATE TABLE close_raw AS
SELECT *
FROM read_csv('data/raw/accounting_close_summary.csv', header = true, all_varchar = true);

-- name: column_types_inferred
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_csv('data/raw/accounting_close_summary.csv'));

-- name: contents
SELECT
    rowid + 2                          AS file_line,
    Period,
    Metric,
    USD,
    TRY_CAST(USD AS DECIMAL(18, 2))    AS usd_parsed,
    length(split_part(USD, '.', 2))    AS usd_decimals
FROM close_raw
ORDER BY file_line;
