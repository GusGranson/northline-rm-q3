-- =============================================================================
-- Profile: data/raw/fx_cad_usd.csv
-- CAD -> USD rates by month: monthly average and month-end.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/fx_cad_usd/NN_<name>.csv.
-- Runner variables: q_start, q_end.
-- =============================================================================

CREATE TABLE fx_raw AS
SELECT *
FROM read_csv('data/raw/fx_cad_usd.csv', header = true, all_varchar = true);

-- name: column_types_inferred
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_csv('data/raw/fx_cad_usd.csv'));

-- name: contents
-- Every row, the decimals each rate carries, and month-end minus average.
SELECT
    rowid + 2                                                       AS file_line,
    Month,
    AvgRate_CADtoUSD,
    MonthEndRate_CADtoUSD,
    length(split_part(AvgRate_CADtoUSD, '.', 2))                    AS avg_decimals,
    length(split_part(MonthEndRate_CADtoUSD, '.', 2))               AS monthend_decimals,
    TRY_CAST(MonthEndRate_CADtoUSD AS DECIMAL(10, 6))
      - TRY_CAST(AvgRate_CADtoUSD AS DECIMAL(10, 6))                AS monthend_minus_avg
FROM fx_raw
ORDER BY file_line;

-- name: month_coverage
-- Every month of Q3 against the months in the file (missing or duplicated months).
WITH q3 AS (
    SELECT strftime(d, '%Y-%m') AS month
    FROM generate_series(getvariable('q_start')::TIMESTAMP, getvariable('q_end')::TIMESTAMP, INTERVAL 1 MONTH) AS t(d)
)
SELECT
    coalesce(q3.month, f.Month)   AS month,
    q3.month IS NOT NULL          AS in_q3,
    count(f.Month)                AS rows_in_file
FROM q3
FULL OUTER JOIN fx_raw AS f ON f.Month = q3.month
GROUP BY ALL
ORDER BY month;
