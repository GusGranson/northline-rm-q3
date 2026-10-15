-- =============================================================================
-- Profile: data/raw/erp_a_sro_transactions.csv
-- ERP-A service repair order (SRO) lines, USD. Weekly exports appended together.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/erp_a_sro_transactions/NN_<name>.csv.
-- Runner variables: q_start, q_end, boundary_days, last_export_at.
-- =============================================================================

-- Verbatim load: every column as text, exactly as written in the file.
CREATE TABLE erp_a_raw AS
SELECT *
FROM read_csv('data/raw/erp_a_sro_transactions.csv', header = true, all_varchar = true);

-- Measurement lens. Parse attempts sit next to the raw text so we can count
-- what parses and how. They are not cleaning decisions and nothing is saved.
CREATE VIEW erp_a AS
SELECT
    rowid + 2                                                   AS file_line,  -- line 1 is the header
    *,
    regexp_replace(TransDate, '[0-9]', '9', 'g')                AS trans_date_shape,
    -- Slash dates are read as MM/DD/YYYY here for profiling only. The evidence
    -- for that reading is in query transdate_slash_ambiguity.
    CASE
        WHEN TransDate LIKE '____-__-__' THEN TRY_STRPTIME(TransDate, '%Y-%m-%d')
        WHEN TransDate LIKE '__/__/____' THEN TRY_STRPTIME(TransDate, '%m/%d/%Y')
    END::DATE                                                   AS trans_date_p,
    TRY_CAST(ExportedAt AS TIMESTAMP)                           AS exported_at_p,
    upper(trim(Whse))                                           AS whse_trim_upper,
    -- First three letters of the trimmed Whse (RIVERTON -> RIV). A lens to see
    -- through spelling variants when counting; the mapping is not decided here.
    left(upper(trim(Whse)), 3)                                  AS whse_prefix3,
    TRY_CAST(Line AS INTEGER)                                   AS line_n,
    TRY_CAST(Oper AS INTEGER)                                   AS oper_n,
    TRY_CAST(TRY_CAST(trim(Acct) AS DECIMAL(10, 1)) AS INTEGER) AS acct_n,
    TRY_CAST(Qty AS DECIMAL(18, 4))                             AS qty_n,
    TRY_CAST(UnitCost AS DECIMAL(18, 4))                        AS unit_cost_n,
    TRY_CAST(ExtCost AS DECIMAL(18, 2))                         AS ext_cost_n
FROM erp_a_raw;


-- ---------------------------------------------------------------------------
-- 1. Row counts, columns and types
-- ---------------------------------------------------------------------------

-- name: file_shape
-- Physical file facts next to what the CSV reader parsed.
WITH f AS (
    SELECT content FROM read_text('data/raw/erp_a_sro_transactions.csv')
),
lines AS (
    SELECT unnest(string_split(content, chr(10))) AS l FROM f
)
SELECT
    (SELECT strlen(content) FROM f)                                    AS bytes,
    (SELECT length(content) - length(replace(content, chr(10), '')) FROM f) AS newline_count,
    (SELECT contains(content, chr(13)) FROM f)                         AS has_carriage_returns,
    (SELECT right(content, 1) = chr(10) FROM f)                        AS ends_with_newline,
    (SELECT left(content, 1) = chr(65279) FROM f)                      AS starts_with_bom,
    (SELECT count(*) FROM lines WHERE trim(l, chr(13) || ' ') = '')    AS blank_lines_incl_final,
    (SELECT count(*) FROM erp_a_raw)                                   AS parsed_data_rows,
    (SELECT count(*) FROM information_schema.columns WHERE table_name = 'erp_a_raw') AS parsed_columns;

-- name: column_types_inferred
-- What DuckDB's CSV sniffer infers per column when left to auto-detect.
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_csv('data/raw/erp_a_sro_transactions.csv'));

-- name: column_profile
-- Per column on the raw text: nulls, distinct values, edge whitespace,
-- how many values parse as integer / decimal, and length range.
WITH long AS (
    FROM erp_a_raw UNPIVOT INCLUDE NULLS (v FOR column_name IN (COLUMNS(*)))
)
SELECT
    c.ordinal_position                                              AS col_pos,
    l.column_name,
    count(*)                                                        AS rows,
    count(*) FILTER (WHERE v IS NULL)                               AS null_or_empty,
    count(*) FILTER (WHERE v IS NOT NULL AND trim(v) = '')          AS whitespace_only,
    count(DISTINCT v)                                               AS distinct_raw,
    count(DISTINCT upper(trim(v)))                                  AS distinct_trimmed_upper,
    count(*) FILTER (WHERE v <> trim(v))                            AS leading_or_trailing_space,
    count(*) FILTER (WHERE TRY_CAST(v AS BIGINT) IS NOT NULL)       AS parses_as_integer,
    count(*) FILTER (WHERE TRY_CAST(v AS DECIMAL(18, 4)) IS NOT NULL) AS parses_as_decimal,
    min(length(v))                                                  AS min_len,
    max(length(v))                                                  AS max_len,
    min(v)                                                          AS min_text,
    max(v)                                                          AS max_text
FROM long AS l
JOIN information_schema.columns AS c
  ON c.table_name = 'erp_a_raw' AND c.column_name = l.column_name
GROUP BY ALL
ORDER BY col_pos;

-- name: amount_precision
-- Decimal places actually used in the numeric columns (as text).
SELECT
    count(*) FILTER (WHERE Qty LIKE '%.%')                          AS qty_with_decimal_point,
    count(*) FILTER (WHERE regexp_matches(UnitCost, '\.\d{3,}$'))   AS unitcost_over_2dp,
    count(*) FILTER (WHERE regexp_matches(ExtCost, '\.\d{3,}$'))    AS extcost_over_2dp,
    count(*) FILTER (WHERE NOT regexp_matches(ExtCost, '\.\d{2}$')) AS extcost_not_exactly_2dp,
    count(*) FILTER (WHERE qty_n IS NULL)                           AS qty_unparsed,
    count(*) FILTER (WHERE unit_cost_n IS NULL)                     AS unitcost_unparsed,
    count(*) FILTER (WHERE ext_cost_n IS NULL)                      AS extcost_unparsed,
    sum(ext_cost_n)                                                 AS ext_cost_all_rows_usd
FROM erp_a;


-- ---------------------------------------------------------------------------
-- 2. Categorical values (brackets make leading/trailing spaces visible)
-- ---------------------------------------------------------------------------

-- name: whse_values
SELECT
    '[' || coalesce(Whse, '<NULL>') || ']' AS whse_raw,
    whse_trim_upper,
    count(*)                               AS rows,
    sum(ext_cost_n)                        AS ext_cost_usd,
    count(*) FILTER (WHERE trans_date_p BETWEEN getvariable('q_start') AND getvariable('q_end'))        AS rows_in_q3,
    sum(ext_cost_n) FILTER (WHERE trans_date_p BETWEEN getvariable('q_start') AND getvariable('q_end')) AS usd_in_q3,
    min(trans_date_p)                      AS min_trans_date,
    max(trans_date_p)                      AS max_trans_date,
    count(DISTINCT SRO)                    AS distinct_sros
FROM erp_a
GROUP BY ALL
ORDER BY whse_trim_upper, whse_raw;

-- name: whse_by_month
-- Raw Whse x transaction month (rows and USD). Elmwood closed 31-Jul-2026.
SELECT * FROM (
    PIVOT (
        SELECT '[' || coalesce(Whse, '<NULL>') || ']' AS whse_raw,
               coalesce(strftime(trans_date_p, '%Y-%m'), 'unparsed') AS m,
               ext_cost_n
        FROM erp_a
    )
    ON m USING count(*) AS rows, sum(ext_cost_n) AS usd
    GROUP BY whse_raw
)
ORDER BY upper(trim(whse_raw, '[] ')), whse_raw;

-- name: oper_values
SELECT
    '[' || coalesce(Oper, '<NULL>') || ']'   AS oper_raw,
    count(*)                                 AS rows,
    sum(ext_cost_n)                          AS ext_cost_usd,
    list_sort(list_distinct(list(acct_n)))   AS accts_used,
    list_sort(list_distinct(list(TransType))) AS transtypes_used
FROM erp_a
GROUP BY oper_raw, oper_n
ORDER BY oper_n, oper_raw;

-- name: oper_by_acct
-- Oper x Acct (Acct read as a number, so ' 6100' and '6100.0' fall under 6100).
SELECT * FROM (
    PIVOT (SELECT oper_n, coalesce(acct_n::VARCHAR, 'unparsed') AS acct, ext_cost_n FROM erp_a)
    ON acct USING count(*) AS rows, sum(ext_cost_n) AS usd
    GROUP BY oper_n
)
ORDER BY oper_n;

-- name: oper_by_month
SELECT * FROM (
    PIVOT (SELECT oper_n, coalesce(strftime(trans_date_p, '%Y-%m'), 'unparsed') AS m, ext_cost_n FROM erp_a)
    ON m USING count(*) AS rows, sum(ext_cost_n) AS usd
    GROUP BY oper_n
)
ORDER BY oper_n;

-- name: sro_oper_sets
-- Which combinations of Oper codes occur within one SRO.
SELECT oper_set, count(*) AS sros, sum(rows) AS rows, sum(usd) AS ext_cost_usd,
       min(SRO) AS min_sro, max(SRO) AS max_sro
FROM (
    SELECT SRO, list_sort(list_distinct(list(oper_n))) AS oper_set, count(*) AS rows, sum(ext_cost_n) AS usd
    FROM erp_a
    GROUP BY SRO
)
GROUP BY oper_set
ORDER BY sros DESC, oper_set;

-- name: transtype_values
SELECT
    '[' || coalesce(TransType, '<NULL>') || ']' AS transtype_raw,
    count(*)                                    AS rows,
    sum(ext_cost_n)                             AS ext_cost_usd,
    list_sort(list_distinct(list(acct_n)))      AS accts_used
FROM erp_a
GROUP BY ALL
ORDER BY transtype_raw;

-- name: transtype_by_acct
SELECT * FROM (
    PIVOT (SELECT TransType, coalesce(acct_n::VARCHAR, 'unparsed') AS acct, ext_cost_n FROM erp_a)
    ON acct USING count(*) AS rows, sum(ext_cost_n) AS usd
    GROUP BY TransType
)
ORDER BY TransType;

-- name: acct_values
SELECT
    '[' || coalesce(Acct, '<NULL>') || ']'    AS acct_raw,
    acct_n,
    count(*)                                  AS rows,
    sum(ext_cost_n)                           AS ext_cost_usd,
    count(*) FILTER (WHERE trans_date_p BETWEEN getvariable('q_start') AND getvariable('q_end'))           AS rows_in_q3,
    sum(ext_cost_n) FILTER (WHERE trans_date_p BETWEEN getvariable('q_start') AND getvariable('q_end'))    AS usd_in_q3,
    list_sort(list_distinct(list(TransType))) AS transtypes_used,
    list_sort(list_distinct(list(whse_trim_upper))) AS whse_used
FROM erp_a
GROUP BY ALL
ORDER BY acct_n, acct_raw;

-- name: acct_raw_format_by_export
-- Does the Acct text format (plain / leading space / '.0') follow the export batch?
SELECT
    ExportedAt,
    count(*) FILTER (WHERE Acct = trim(Acct) AND Acct NOT LIKE '%.%') AS acct_plain,
    count(*) FILTER (WHERE Acct <> trim(Acct))                        AS acct_leading_trailing_space,
    count(*) FILTER (WHERE Acct LIKE '%.0')                           AS acct_dot_zero,
    count(*) FILTER (WHERE trans_date_shape <> '9999-99-99')          AS transdate_not_iso,
    count(*) FILTER (WHERE Whse <> whse_trim_upper)                   AS whse_not_trimmed_upper,
    count(*)                                                          AS rows
FROM erp_a
GROUP BY ExportedAt
ORDER BY ExportedAt;

-- name: custnum_by_acct
-- CustNum present or not, by account (README rule 1: account decides, not CustNum).
SELECT
    acct_n,
    count(*) FILTER (WHERE CustNum IS NOT NULL)            AS rows_with_custnum,
    sum(ext_cost_n) FILTER (WHERE CustNum IS NOT NULL)     AS usd_with_custnum,
    count(*) FILTER (WHERE CustNum IS NULL)                AS rows_without_custnum,
    sum(ext_cost_n) FILTER (WHERE CustNum IS NULL)         AS usd_without_custnum
FROM erp_a
GROUP BY acct_n
ORDER BY acct_n;

-- name: id_shapes
-- Text shapes of identifier columns (digits shown as 9, letters as A).
SELECT 'SRO' AS column_name,
       regexp_replace(regexp_replace(SRO, '[0-9]', '9', 'g'), '[A-Za-z]', 'A', 'g') AS shape,
       count(*) AS rows, min(SRO) AS min_text, max(SRO) AS max_text
FROM erp_a GROUP BY ALL
UNION ALL
SELECT 'Line', regexp_replace(Line, '[0-9]', '9', 'g'), count(*), min(Line), max(Line)
FROM erp_a GROUP BY ALL
UNION ALL
SELECT 'CustNum',
       coalesce(regexp_replace(regexp_replace(CustNum, '[0-9]', '9', 'g'), '[A-Za-z]', 'A', 'g'), '<NULL>'),
       count(*), min(CustNum), max(CustNum)
FROM erp_a GROUP BY ALL
ORDER BY column_name, rows DESC;

-- name: item_values
SELECT
    Item,
    count(*)                                  AS rows,
    sum(ext_cost_n)                           AS ext_cost_usd,
    list_sort(list_distinct(list(acct_n)))    AS accts_used,
    list_sort(list_distinct(list(TransType))) AS transtypes_used,
    list_sort(list_distinct(list(oper_n)))    AS opers_used
FROM erp_a
GROUP BY Item
ORDER BY Item;

-- name: sro_multi_whse
-- SROs whose lines carry more than one Whse, after looking through spelling
-- variants (whse_prefix3).
SELECT
    SRO,
    list_sort(list_distinct(list(Whse)))            AS whse_raw_values,
    list_sort(list_distinct(list(whse_prefix3)))    AS whse_prefix3_values,
    min(trans_date_p)                               AS min_trans_date,
    max(trans_date_p)                               AS max_trans_date,
    count(*)                                        AS rows,
    sum(ext_cost_n)                                 AS ext_cost_usd
FROM erp_a
GROUP BY SRO
HAVING count(DISTINCT whse_prefix3) > 1
ORDER BY SRO;

-- name: prefix_month_acct
-- Rows and USD by Whse prefix x transaction month x account. Overview only.
SELECT
    whse_prefix3,
    strftime(trans_date_p, '%Y-%m') AS trans_month,
    acct_n,
    count(*)                        AS rows,
    sum(ext_cost_n)                 AS ext_cost_usd
FROM erp_a
GROUP BY ALL
ORDER BY ALL;


-- name: samples_by_oper
-- First 3 rows (file order) per Oper, for citing evidence.
SELECT file_line, SRO, Line, Oper, Whse, TransDate, TransType, Acct, Item, Qty, UnitCost, ExtCost, CustNum, ExportedAt
FROM erp_a
QUALIFY row_number() OVER (PARTITION BY oper_n ORDER BY file_line) <= 3
ORDER BY oper_n, file_line;

-- name: samples_by_prefix_month
-- First 2 rows (file order) per Whse prefix x transaction month, for citing evidence.
SELECT whse_prefix3, strftime(trans_date_p, '%Y-%m') AS trans_month,
       file_line, SRO, Line, Oper, Whse, TransDate, TransType, Acct, Item, Qty, UnitCost, ExtCost, CustNum, ExportedAt
FROM erp_a
QUALIFY row_number() OVER (PARTITION BY whse_prefix3, strftime(trans_date_p, '%Y-%m') ORDER BY file_line) <= 2
ORDER BY whse_prefix3, trans_month, file_line;


-- ---------------------------------------------------------------------------
-- 3. Dates
-- ---------------------------------------------------------------------------

-- name: transdate_formats
SELECT
    trans_date_shape,
    count(*)                  AS rows,
    count(trans_date_p)       AS parsed_rows,
    min(trans_date_p)         AS min_date,
    max(trans_date_p)         AS max_date,
    sum(ext_cost_n)           AS ext_cost_usd,
    min(TransDate)            AS example_min_text,
    max(TransDate)            AS example_max_text
FROM erp_a
GROUP BY trans_date_shape
ORDER BY rows DESC;

-- name: transdate_slash_ambiguity
-- For NN/NN/YYYY values: a part above 12 can only be a day. If no first part
-- exceeds 12 but some second parts do, MM/DD/YYYY is evidenced. Values where
-- both parts are 12 or less (and differ) read as two different dates.
WITH s AS (
    SELECT *,
           split_part(TransDate, '/', 1)::INTEGER AS p1,
           split_part(TransDate, '/', 2)::INTEGER AS p2
    FROM erp_a
    WHERE trans_date_shape = '99/99/9999'
)
SELECT
    count(*)                                                     AS slash_rows,
    count(*) FILTER (WHERE p1 > 12)                              AS first_part_over_12,
    count(*) FILTER (WHERE p2 > 12)                              AS second_part_over_12,
    count(*) FILTER (WHERE p1 <= 12 AND p2 <= 12 AND p1 <> p2)   AS ambiguous_rows,
    sum(ext_cost_n) FILTER (WHERE p1 <= 12 AND p2 <= 12 AND p1 <> p2) AS ambiguous_usd,
    count(*) FILTER (WHERE p1 = p2)                              AS same_either_way
FROM s;

-- name: transdate_slash_by_reading
-- Ambiguous slash dates: month under MM/DD vs DD/MM reading.
SELECT
    strftime(TRY_STRPTIME(TransDate, '%m/%d/%Y'), '%Y-%m') AS month_if_mm_dd,
    strftime(TRY_STRPTIME(TransDate, '%d/%m/%Y'), '%Y-%m') AS month_if_dd_mm,
    count(*)                                               AS rows,
    sum(ext_cost_n)                                        AS ext_cost_usd
FROM erp_a
WHERE trans_date_shape = '99/99/9999'
  AND split_part(TransDate, '/', 1)::INTEGER <= 12
  AND split_part(TransDate, '/', 2)::INTEGER <= 12
GROUP BY ALL
ORDER BY ALL;

-- name: transdate_by_month
SELECT
    strftime(trans_date_p, '%Y-%m')                                   AS trans_month,
    CASE WHEN trans_date_p < getvariable('q_start') THEN 'before Q3'
         WHEN trans_date_p > getvariable('q_end')   THEN 'after Q3'
         ELSE 'in Q3' END                                            AS vs_quarter,
    count(*)                                                          AS rows,
    count(*) FILTER (WHERE trans_date_shape = '99/99/9999')           AS slash_format_rows,
    sum(ext_cost_n) FILTER (WHERE trans_date_shape = '99/99/9999')    AS slash_format_usd,
    sum(ext_cost_n)                                                   AS ext_cost_usd,
    count(*) FILTER (WHERE qty_n < 0)                                 AS negative_qty_rows,
    sum(ext_cost_n) FILTER (WHERE qty_n < 0)                          AS negative_qty_usd
FROM erp_a
GROUP BY ALL
ORDER BY trans_month;

-- name: transdate_daily_near_boundaries
-- Every day before Q3 start + boundary_days and after Q3 end - boundary_days.
SELECT
    trans_date_p,
    CASE WHEN trans_date_p < getvariable('q_start') THEN 'before Q3'
         WHEN trans_date_p > getvariable('q_end')   THEN 'after Q3'
         ELSE 'in Q3' END                                         AS vs_quarter,
    count(*)                                                      AS rows,
    count(*) FILTER (WHERE trans_date_shape = '99/99/9999')       AS slash_format_rows,
    sum(ext_cost_n)                                               AS ext_cost_usd,
    list_sort(list_distinct(list(ExportedAt)))                    AS in_exports
FROM erp_a
WHERE trans_date_p < getvariable('q_start') + getvariable('boundary_days')
   OR trans_date_p > getvariable('q_end') - getvariable('boundary_days')
GROUP BY ALL
ORDER BY trans_date_p;

-- name: outside_quarter_by_acct
SELECT
    CASE WHEN trans_date_p < getvariable('q_start') THEN 'before Q3' ELSE 'after Q3' END AS vs_quarter,
    acct_n,
    count(*)        AS rows,
    sum(ext_cost_n) AS ext_cost_usd
FROM erp_a
WHERE trans_date_p NOT BETWEEN getvariable('q_start') AND getvariable('q_end')
GROUP BY ALL
ORDER BY vs_quarter, acct_n;

-- name: exports_summary
-- One row per export batch: what transaction dates it carries.
SELECT
    ExportedAt,
    dayname(exported_at_p)                                      AS export_weekday,
    exported_at_p > getvariable('last_export_at')              AS after_readme_last_export,
    count(*)                                                    AS rows,
    min(trans_date_p)                                           AS min_trans_date,
    max(trans_date_p)                                           AS max_trans_date,
    count(*) FILTER (WHERE trans_date_p > exported_at_p::DATE)  AS rows_dated_after_export,
    count(DISTINCT SRO)                                         AS distinct_sros,
    sum(ext_cost_n)                                             AS ext_cost_usd
FROM erp_a
GROUP BY ALL
ORDER BY ExportedAt;

-- name: exports_by_acct
-- USD by export batch x account (all transaction dates).
SELECT * FROM (
    PIVOT (SELECT ExportedAt, coalesce(acct_n::VARCHAR, 'unparsed') AS acct, ext_cost_n FROM erp_a)
    ON acct USING count(*) AS rows, sum(ext_cost_n) AS usd
    GROUP BY ExportedAt
)
ORDER BY ExportedAt;

-- name: transdate_to_export_lag
-- Days from transaction date to the export that carries the line.
SELECT
    date_diff('day', trans_date_p, exported_at_p::DATE) AS days_trans_to_export,
    count(*)                                            AS rows,
    sum(ext_cost_n)                                     AS ext_cost_usd
FROM erp_a
GROUP BY ALL
ORDER BY days_trans_to_export;


-- ---------------------------------------------------------------------------
-- 4. Duplicates
-- ---------------------------------------------------------------------------

-- name: dup_exact_all_columns
-- Rows identical in all 13 raw columns, ExportedAt included.
WITH g AS (
    SELECT *, count(*) AS copies FROM erp_a_raw GROUP BY ALL HAVING count(*) > 1
)
SELECT
    copies,
    count(*)                                             AS groups,
    sum(copies)                                          AS rows_in_groups,
    sum(copies - 1)                                      AS surplus_rows,
    sum((copies - 1) * TRY_CAST(ExtCost AS DECIMAL(18, 2))) AS surplus_usd
FROM g
GROUP BY copies
ORDER BY copies;

-- name: dup_raw_excl_exportedat
-- Rows identical in the 12 raw columns other than ExportedAt.
WITH g AS (
    SELECT * EXCLUDE (ExportedAt),
           count(*)                   AS copies,
           count(DISTINCT ExportedAt) AS exports
    FROM erp_a_raw
    GROUP BY ALL
    HAVING count(*) > 1
)
SELECT
    copies,
    exports,
    count(*)                                             AS groups,
    sum(copies)                                          AS rows_in_groups,
    sum(copies - 1)                                      AS surplus_rows,
    sum((copies - 1) * TRY_CAST(ExtCost AS DECIMAL(18, 2))) AS surplus_usd
FROM g
GROUP BY ALL
ORDER BY ALL;

-- name: dup_normalized_excl_exportedat
-- Same as above, but compared after trimming/upper-casing text, reading Acct and
-- amounts as numbers and dates via the lens. Catches copies that differ only
-- in formatting (e.g. '6100' vs '6100.0', ISO vs slash date, 'riv' vs 'RIV ').
WITH g AS (
    SELECT
        SRO, line_n, oper_n, whse_trim_upper, trans_date_p, trim(TransType) AS tt, acct_n,
        trim(Item) AS item, qty_n, unit_cost_n, ext_cost_n, trim(CustNum) AS cust,
        count(*)                                        AS copies,
        count(DISTINCT ExportedAt)                      AS exports,
        count(DISTINCT (Whse, TransDate, Acct))         AS raw_format_variants
    FROM erp_a
    GROUP BY ALL
    HAVING count(*) > 1
)
SELECT
    copies,
    exports,
    raw_format_variants,
    count(*)                         AS groups,
    sum(copies)                      AS rows_in_groups,
    sum(copies - 1)                  AS surplus_rows,
    sum((copies - 1) * ext_cost_n)   AS surplus_usd
FROM g
GROUP BY ALL
ORDER BY ALL;

-- name: dup_sro_line_summary
-- SRO+Line groups with more than one row, classified by how many exports
-- they span and how many distinct line contents (normalized, excl. ExportedAt)
-- they hold. USD shown under three readings so the impact is visible; none is
-- a decision.
WITH r AS (
    SELECT *,
           max(exported_at_p) OVER (PARTITION BY SRO, Line) AS grp_last_export,
           min(exported_at_p) OVER (PARTITION BY SRO, Line) AS grp_first_export,
           count(*)           OVER (PARTITION BY SRO, Line) AS grp_rows
    FROM erp_a
),
g AS (
    SELECT
        SRO, Line,
        count(*)                                                  AS rows,
        count(DISTINCT ExportedAt)                                AS exports,
        count(DISTINCT (oper_n, whse_trim_upper, trans_date_p, trim(TransType), acct_n,
                        trim(Item), qty_n, unit_cost_n, ext_cost_n, trim(CustNum))) AS content_variants,
        bool_or(qty_n < 0) AND bool_or(qty_n > 0)                 AS mixes_qty_sign,
        sum(ext_cost_n)                                           AS usd_all_rows,
        sum(ext_cost_n) FILTER (WHERE exported_at_p = grp_last_export)  AS usd_last_export_rows,
        sum(ext_cost_n) FILTER (WHERE exported_at_p = grp_first_export) AS usd_first_export_rows
    FROM r
    WHERE grp_rows > 1
    GROUP BY SRO, Line
)
SELECT
    rows, exports, content_variants, mixes_qty_sign,
    count(*)                    AS groups,
    sum(rows)                   AS rows_in_groups,
    sum(usd_all_rows)           AS usd_all_rows,
    sum(usd_last_export_rows)   AS usd_last_export_rows_only,
    sum(usd_first_export_rows)  AS usd_first_export_rows_only
FROM g
GROUP BY ALL
ORDER BY ALL;

-- name: dup_sro_line_differing_columns
-- Within SRO+Line groups that hold more than one row: in how many groups
-- does each column take more than one value (raw text / lens value)?
WITH g AS (
    SELECT
        SRO, Line,
        count(DISTINCT ExportedAt) > 1                    AS ExportedAt,
        count(DISTINCT Oper) > 1                          AS Oper,
        count(DISTINCT Whse) > 1                          AS Whse_raw,
        count(DISTINCT whse_trim_upper) > 1               AS Whse_trim_upper,
        count(DISTINCT whse_prefix3) > 1                  AS Whse_prefix3,
        count(DISTINCT TransDate) > 1                     AS TransDate_raw,
        count(DISTINCT trans_date_p) > 1                  AS TransDate_parsed,
        count(DISTINCT TransType) > 1                     AS TransType,
        count(DISTINCT Acct) > 1                          AS Acct_raw,
        count(DISTINCT acct_n) > 1                        AS Acct_number,
        count(DISTINCT Item) > 1                          AS Item,
        count(DISTINCT qty_n) > 1                         AS Qty,
        count(DISTINCT unit_cost_n) > 1                   AS UnitCost,
        count(DISTINCT ext_cost_n) > 1                    AS ExtCost,
        count(DISTINCT coalesce(CustNum, '<NULL>')) > 1   AS CustNum
    FROM erp_a
    GROUP BY SRO, Line
    HAVING count(*) > 1
)
SELECT column_name, count(*) FILTER (WHERE differs) AS groups_where_column_differs, count(*) AS groups_total
FROM (FROM g UNPIVOT (differs FOR column_name IN (COLUMNS(* EXCLUDE (SRO, Line)))))
GROUP BY column_name
ORDER BY groups_where_column_differs DESC, column_name;

-- name: dup_sro_line_export_pairs
-- Which export batches the repeated SRO+Line groups appear in.
SELECT
    exports_holding_the_line,
    count(*)  AS groups,
    sum(rows) AS rows
FROM (
    SELECT SRO, Line, list_sort(list(ExportedAt)) AS exports_holding_the_line, count(*) AS rows
    FROM erp_a
    GROUP BY SRO, Line
    HAVING count(*) > 1
)
GROUP BY exports_holding_the_line
ORDER BY groups DESC, exports_holding_the_line;

-- name: dup_sro_line_variant_rows
-- Every row of an SRO+Line group whose rows differ in content (normalized,
-- excl. ExportedAt), ordered so versions sit together.
WITH g AS (
    SELECT SRO, Line
    FROM erp_a
    GROUP BY SRO, Line
    HAVING count(DISTINCT (oper_n, whse_trim_upper, trans_date_p, trim(TransType), acct_n,
                           trim(Item), qty_n, unit_cost_n, ext_cost_n, trim(CustNum))) > 1
)
SELECT a.file_line, a.SRO, a.Line, a.Oper, a.Whse, a.TransDate, a.trans_date_p, a.TransType,
       a.Acct, a.Item, a.Qty, a.UnitCost, a.ExtCost, a.CustNum, a.ExportedAt
FROM erp_a AS a
JOIN g USING (SRO, Line)
ORDER BY a.SRO, a.Line, a.exported_at_p, a.file_line;

-- name: dup_sro_line_identical_samples
-- 15 sample groups whose repeated rows are identical apart from formatting/ExportedAt.
WITH g AS (
    SELECT SRO, Line
    FROM erp_a
    GROUP BY SRO, Line
    HAVING count(*) > 1
       AND count(DISTINCT (oper_n, whse_trim_upper, trans_date_p, trim(TransType), acct_n,
                           trim(Item), qty_n, unit_cost_n, ext_cost_n, trim(CustNum))) = 1
    ORDER BY SRO, Line
    LIMIT 15
)
SELECT a.file_line, a.SRO, a.Line, a.Oper, a.Whse, a.TransDate, a.TransType,
       a.Acct, a.Item, a.Qty, a.UnitCost, a.ExtCost, a.CustNum, a.ExportedAt
FROM erp_a AS a
JOIN g USING (SRO, Line)
ORDER BY a.SRO, a.Line, a.exported_at_p, a.file_line;


-- ---------------------------------------------------------------------------
-- 5. Negative quantities and amounts
-- ---------------------------------------------------------------------------

-- name: sign_combinations
SELECT
    CASE WHEN qty_n < 0 THEN '-' WHEN qty_n = 0 THEN '0' ELSE '+' END             AS qty_sign,
    CASE WHEN unit_cost_n < 0 THEN '-' WHEN unit_cost_n = 0 THEN '0' ELSE '+' END AS unitcost_sign,
    CASE WHEN ext_cost_n < 0 THEN '-' WHEN ext_cost_n = 0 THEN '0' ELSE '+' END   AS extcost_sign,
    count(*)        AS rows,
    sum(ext_cost_n) AS ext_cost_usd
FROM erp_a
GROUP BY ALL
ORDER BY ALL;

-- name: negative_rows
-- Every row with a negative Qty, UnitCost or ExtCost, with the candidate
-- originals it could reverse: same SRO, Oper, Acct, Item and UnitCost, and
-- the opposite Qty.
SELECT
    n.file_line, n.SRO, n.Line, n.Oper, n.Whse, n.TransDate, n.trans_date_p, n.TransType,
    n.Acct, n.Item, n.Qty, n.UnitCost, n.ExtCost, n.CustNum, n.ExportedAt,
    count(o.file_line)                      AS candidate_originals,
    list_sort(list(o.file_line))            AS candidate_original_lines,
    list_sort(list(DISTINCT o.Line))        AS candidate_original_line_numbers,
    min(o.trans_date_p)                     AS candidate_original_min_date,
    max(o.trans_date_p)                     AS candidate_original_max_date
FROM erp_a AS n
LEFT JOIN erp_a AS o
       ON o.SRO = n.SRO AND o.oper_n = n.oper_n AND o.acct_n = n.acct_n
      AND trim(o.Item) = trim(n.Item) AND o.unit_cost_n = n.unit_cost_n
      AND o.qty_n = -n.qty_n
WHERE n.qty_n < 0 OR n.unit_cost_n < 0 OR n.ext_cost_n < 0
GROUP BY ALL
ORDER BY n.file_line;

-- name: negative_summary
-- Negative-Qty rows by month and by where their candidate original sits.
WITH n AS (
    SELECT
        n.file_line, n.SRO, n.Line, n.trans_date_p, n.ext_cost_n, n.acct_n,
        count(o.file_line)                AS originals,
        bool_or(o.Line = n.Line)          AS original_shares_line_number,
        min(o.trans_date_p)               AS orig_min_date,
        max(o.trans_date_p)               AS orig_max_date
    FROM erp_a AS n
    LEFT JOIN erp_a AS o
           ON o.SRO = n.SRO AND o.oper_n = n.oper_n AND o.acct_n = n.acct_n
          AND trim(o.Item) = trim(n.Item) AND o.unit_cost_n = n.unit_cost_n
          AND o.qty_n = -n.qty_n
    WHERE n.qty_n < 0
    GROUP BY ALL
)
SELECT
    strftime(trans_date_p, '%Y-%m')                                AS reversal_month,
    CASE WHEN originals = 0 THEN 'no candidate original in file'
         WHEN orig_max_date < getvariable('q_start') THEN 'original before Q3'
         WHEN orig_min_date > getvariable('q_end') THEN 'original after Q3'
         WHEN strftime(orig_min_date, '%Y-%m') = strftime(trans_date_p, '%Y-%m')
          AND strftime(orig_max_date, '%Y-%m') = strftime(trans_date_p, '%Y-%m') THEN 'original same month'
         ELSE 'original other Q3 month' END                         AS original_position,
    coalesce(original_shares_line_number, false)                   AS original_shares_line_number,
    count(*)                                                       AS reversal_rows,
    sum(ext_cost_n)                                                AS reversal_usd
FROM n
GROUP BY ALL
ORDER BY ALL;


-- name: negative_by_oper_acct
SELECT oper_n, acct_n, count(*) AS negative_qty_rows, sum(ext_cost_n) AS negative_qty_usd
FROM erp_a
WHERE qty_n < 0
GROUP BY ALL
ORDER BY ALL;


-- ---------------------------------------------------------------------------
-- 6. ExtCost vs Qty x UnitCost
-- ---------------------------------------------------------------------------

-- name: extcost_check_summary
WITH c AS (
    SELECT *, round(qty_n * unit_cost_n, 2) AS calc
    FROM erp_a
)
SELECT
    CASE WHEN ext_cost_n IS NULL OR qty_n IS NULL OR unit_cost_n IS NULL THEN 'unparseable'
         WHEN ext_cost_n = calc THEN 'match'
         WHEN abs(ext_cost_n - calc) <= 0.01 THEN 'off by 1 cent'
         ELSE 'mismatch' END     AS result,
    count(*)                     AS rows,
    sum(ext_cost_n)              AS ext_cost_usd,
    sum(calc)                    AS qty_x_unitcost_usd,
    sum(ext_cost_n - calc)       AS difference_usd
FROM c
GROUP BY ALL
ORDER BY ALL;

-- name: extcost_mismatch_rows
WITH c AS (
    SELECT *, round(qty_n * unit_cost_n, 2) AS calc
    FROM erp_a
)
SELECT
    file_line, SRO, Line, Oper, Whse, TransDate, TransType, Acct, Item, Qty, UnitCost, ExtCost,
    calc                                         AS qty_x_unitcost,
    ext_cost_n - calc                            AS difference,
    round(ext_cost_n / nullif(calc, 0), 4)       AS ratio_ext_to_calc,
    ExportedAt
FROM c
WHERE ext_cost_n <> calc
ORDER BY file_line;
