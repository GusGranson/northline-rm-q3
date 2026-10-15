-- =============================================================================
-- Profile: data/raw/erp_b_lakeshore_gl_detail.xlsx
-- ERP-B general ledger detail for Lakeshore (LKS), CAD.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/erp_b_lakeshore_gl_detail/NN_<name>.csv.
-- Runner variables: q_start, q_end, boundary_days.
-- =============================================================================

INSTALL excel;
LOAD excel;

-- Verbatim load: every cell as text, blank rows kept (stop_at_empty = false).
CREATE TABLE erp_b_raw AS
SELECT *
FROM read_xlsx('data/raw/erp_b_lakeshore_gl_detail.xlsx',
               header = true, all_varchar = true, stop_at_empty = false);

CREATE TABLE account_map_raw AS
SELECT *
FROM read_csv('data/raw/account_map_lakeshore.csv', header = true, all_varchar = true);

-- Measurement lens. Parse attempts sit next to the raw text; nothing is saved.
CREATE VIEW erp_b AS
SELECT
    rowid + 2                                          AS excel_row,  -- row 1 is the header
    *,
    regexp_replace(PostingDate, '[0-9]', '9', 'g')     AS posting_date_shape,
    -- DD/MM/YYYY for profiling only; evidence in query posting_date_ambiguity.
    TRY_STRPTIME(PostingDate, '%d/%m/%Y')::DATE        AS posting_date_p,
    -- Some amount cells are text with thousands separators ('4,581.93'); the
    -- lens strips the comma so sums include them. Those cells are listed in
    -- query amount_nonplain_rows. Float artifacts (553.5599999999999) round to cents.
    TRY_CAST(replace(AmountCAD, ',', '') AS DECIMAL(18, 2)) AS amount_cad_n,
    regexp_replace(AmountCAD, '[0-9]', '9', 'g')       AS amount_shape,
    -- Row kind from what is observed in the sheet (see journalid_shapes).
    CASE
        WHEN coalesce(trim(JournalID), '') = '' AND coalesce(trim(PostingDate), '') = ''
         AND coalesce(trim(LocalAccount), '') = '' AND coalesce(trim(Description), '') = ''
         AND coalesce(trim(AmountCAD), '') = '' AND coalesce(trim(Source), '') = ''
            THEN 'blank'
        WHEN regexp_full_match(JournalID, 'LK[0-9]+') THEN 'journal line'
        ELSE 'other: ' || coalesce(JournalID, '<NULL>')
    END                                                AS row_kind
FROM erp_b_raw;


-- ---------------------------------------------------------------------------
-- 1. Row counts, columns and types
-- ---------------------------------------------------------------------------

-- name: row_kinds
SELECT
    row_kind,
    count(*)            AS rows,
    min(excel_row)      AS first_excel_row,
    max(excel_row)      AS last_excel_row,
    sum(amount_cad_n)   AS amount_cad
FROM erp_b
GROUP BY row_kind
UNION ALL
SELECT 'ALL ROWS', count(*), min(excel_row), max(excel_row), sum(amount_cad_n) FROM erp_b
ORDER BY rows DESC;

-- name: column_types_inferred
-- What DuckDB infers per column when the sheet is read without all_varchar.
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_xlsx('data/raw/erp_b_lakeshore_gl_detail.xlsx', stop_at_empty = false));

-- name: column_profile
WITH long AS (
    FROM erp_b_raw UNPIVOT INCLUDE NULLS (v FOR column_name IN (COLUMNS(*)))
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
    count(*) FILTER (WHERE TRY_CAST(v AS DECIMAL(18, 4)) IS NOT NULL) AS parses_as_decimal,
    min(length(v))                                                  AS min_len,
    max(length(v))                                                  AS max_len,
    min(v)                                                          AS min_text,
    max(v)                                                          AS max_text
FROM long AS l
JOIN information_schema.columns AS c
  ON c.table_name = 'erp_b_raw' AND c.column_name = l.column_name
GROUP BY ALL
ORDER BY col_pos;

-- name: amount_text_shapes
-- How AmountCAD reads as text. A numeric cell shows as plain digits (binary
-- float artifacts appear as 13+ decimals); a text cell keeps its formatting.
SELECT
    CASE WHEN regexp_full_match(AmountCAD, '-?[0-9]+(\.[0-9]{1,2})?') THEN 'plain, <= 2 decimals'
         WHEN regexp_full_match(AmountCAD, '-?[0-9]+\.[0-9]{3,}')
              AND abs(AmountCAD::DOUBLE * 100 - round(AmountCAD::DOUBLE * 100)) < 1e-6
              THEN 'float artifact, rounds to cents'
         WHEN regexp_full_match(AmountCAD, '-?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]{1,2})?') THEN 'text with thousands separator'
         ELSE 'other' END                              AS amount_text_class,
    row_kind,
    count(*)                                           AS rows,
    count(*) FILTER (WHERE TRY_CAST(AmountCAD AS DECIMAL(18, 2)) IS NULL) AS fails_plain_numeric_parse,
    sum(amount_cad_n)                                  AS amount_cad_lens
FROM erp_b
GROUP BY ALL
ORDER BY ALL;

-- name: amount_nonplain_rows
-- Every amount cell that is not plain digits with up to 2 decimals.
SELECT excel_row, JournalID, PostingDate, LocalAccount, Description, AmountCAD,
       amount_cad_n AS amount_cad_lens, Source, row_kind
FROM erp_b
WHERE NOT regexp_full_match(AmountCAD, '-?[0-9]+(\.[0-9]{1,2})?')
ORDER BY excel_row;

-- name: text_amounts_by_account_month
-- The amounts stored as text with a thousands separator, by account and month.
SELECT
    LocalAccount,
    strftime(posting_date_p, '%Y-%m') AS posting_month,
    count(*)                          AS rows,
    sum(amount_cad_n)                 AS amount_cad_lens
FROM erp_b
WHERE regexp_full_match(AmountCAD, '-?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]{1,2})?')
GROUP BY ALL
ORDER BY ALL;

-- name: journalid_shapes
SELECT
    regexp_replace(regexp_replace(coalesce(JournalID, '<NULL>'), '[0-9]', '9', 'g'), '[a-z]', 'a', 'g') AS shape,
    count(*)       AS rows,
    min(JournalID) AS min_text,
    max(JournalID) AS max_text
FROM erp_b
GROUP BY shape
ORDER BY rows DESC;


-- ---------------------------------------------------------------------------
-- 2. Non-data rows (subtotals, blanks)
-- ---------------------------------------------------------------------------

-- name: non_data_rows
SELECT excel_row, JournalID, PostingDate, LocalAccount, Description, AmountCAD, Source, row_kind
FROM erp_b
WHERE row_kind <> 'journal line'
ORDER BY excel_row;

-- name: subtotal_check
-- Does each SUBTOTAL row equal the journal lines above it since the previous
-- non-data row (its block)? And the journal lines with the same account and
-- posting month anywhere in the sheet?
WITH b AS (
    SELECT *,
           count(*) FILTER (WHERE row_kind <> 'journal line')
               OVER (ORDER BY excel_row ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS block_no
    FROM erp_b
),
block_sums AS (
    SELECT coalesce(block_no, 0) AS block_no, count(*) AS lines, sum(amount_cad_n) AS lines_cad,
           list_sort(list_distinct(list(LocalAccount))) AS accounts,
           list_sort(list_distinct(list(strftime(posting_date_p, '%Y-%m')))) AS months
    FROM b WHERE row_kind = 'journal line'
    GROUP BY ALL
),
acct_month AS (
    SELECT LocalAccount, strftime(posting_date_p, '%Y-%m') AS m, sum(amount_cad_n) AS cad
    FROM erp_b WHERE row_kind = 'journal line'
    GROUP BY ALL
)
SELECT
    s.excel_row, s.LocalAccount, s.PostingDate, s.Description,
    s.amount_cad_n                          AS subtotal_cad,
    bs.lines                                AS block_lines,
    bs.accounts                             AS block_accounts,
    bs.months                               AS block_months,
    bs.lines_cad                            AS block_lines_cad,
    s.amount_cad_n - bs.lines_cad           AS diff_vs_block,
    am.cad                                  AS same_acct_month_cad,
    s.amount_cad_n - am.cad                 AS diff_vs_acct_month
FROM b AS s
LEFT JOIN block_sums AS bs ON bs.block_no = coalesce(s.block_no, 0)
LEFT JOIN acct_month AS am
       ON am.LocalAccount = s.LocalAccount
      AND am.m = strftime(s.posting_date_p, '%Y-%m')
WHERE s.row_kind <> 'journal line'
ORDER BY s.excel_row;


-- ---------------------------------------------------------------------------
-- 3. Categorical values
-- ---------------------------------------------------------------------------

-- name: localaccount_values
SELECT
    '[' || coalesce(LocalAccount, '<NULL>') || ']'                AS localaccount_raw,
    count(*) FILTER (WHERE row_kind = 'journal line')             AS journal_lines,
    sum(amount_cad_n) FILTER (WHERE row_kind = 'journal line')    AS journal_cad,
    count(*) FILTER (WHERE row_kind <> 'journal line')            AS non_data_rows,
    sum(amount_cad_n) FILTER (WHERE row_kind <> 'journal line')   AS non_data_cad
FROM erp_b
GROUP BY ALL
ORDER BY localaccount_raw;

-- name: source_values
SELECT
    '[' || coalesce(Source, '<NULL>') || ']' AS source_raw,
    row_kind,
    count(*)                                 AS rows,
    sum(amount_cad_n)                        AS amount_cad
FROM erp_b
GROUP BY ALL
ORDER BY row_kind, source_raw;

-- name: source_by_account
SELECT * FROM (
    PIVOT (SELECT LocalAccount, coalesce(Source, '<NULL>') AS src, amount_cad_n
           FROM erp_b WHERE row_kind = 'journal line')
    ON src USING count(*) AS rows, sum(amount_cad_n) AS cad
    GROUP BY LocalAccount
)
ORDER BY LocalAccount;

-- name: samples_by_account
-- First 3 journal lines (sheet order) per local account, for citing evidence.
SELECT excel_row, JournalID, PostingDate, LocalAccount, Description, AmountCAD, Source
FROM erp_b
WHERE row_kind = 'journal line'
QUALIFY row_number() OVER (PARTITION BY LocalAccount ORDER BY excel_row) <= 3
ORDER BY LocalAccount, excel_row;

-- name: description_by_account
SELECT
    LocalAccount,
    Description,
    count(*)          AS journal_lines,
    sum(amount_cad_n) AS journal_cad
FROM erp_b
WHERE row_kind = 'journal line'
GROUP BY ALL
ORDER BY LocalAccount, Description;


-- ---------------------------------------------------------------------------
-- 4. Dates
-- ---------------------------------------------------------------------------

-- name: posting_date_formats
SELECT
    posting_date_shape,
    row_kind,
    count(*)                 AS rows,
    count(posting_date_p)    AS parsed_rows,
    min(posting_date_p)      AS min_date,
    max(posting_date_p)      AS max_date
FROM erp_b
GROUP BY ALL
ORDER BY ALL;

-- name: posting_date_ambiguity
-- For NN/NN/YYYY: a part above 12 can only be a day.
WITH s AS (
    SELECT *,
           split_part(PostingDate, '/', 1)::INTEGER AS p1,
           split_part(PostingDate, '/', 2)::INTEGER AS p2
    FROM erp_b
    WHERE posting_date_shape = '99/99/9999'
)
SELECT
    count(*)                                                    AS slash_rows,
    count(*) FILTER (WHERE p1 > 12)                             AS first_part_over_12,
    count(*) FILTER (WHERE p2 > 12)                             AS second_part_over_12,
    count(*) FILTER (WHERE p1 <= 12 AND p2 <= 12 AND p1 <> p2)  AS ambiguous_rows,
    sum(amount_cad_n) FILTER (WHERE p1 <= 12 AND p2 <= 12 AND p1 <> p2 AND row_kind = 'journal line') AS ambiguous_journal_cad
FROM s;

-- name: posting_month_by_account
-- Journal lines only: rows and CAD by local account x posting month.
SELECT * FROM (
    PIVOT (SELECT LocalAccount, coalesce(strftime(posting_date_p, '%Y-%m'), 'unparsed') AS m, amount_cad_n
           FROM erp_b WHERE row_kind = 'journal line')
    ON m USING count(*) AS rows, sum(amount_cad_n) AS cad
    GROUP BY LocalAccount
)
ORDER BY LocalAccount;

-- name: rows_near_boundaries
-- Journal lines within boundary_days of Q3's first and last day, either side.
SELECT
    excel_row, JournalID, PostingDate, posting_date_p,
    CASE WHEN posting_date_p < getvariable('q_start') THEN 'before Q3'
         WHEN posting_date_p > getvariable('q_end')   THEN 'after Q3'
         ELSE 'in Q3' END AS vs_quarter,
    LocalAccount, Description, AmountCAD, Source
FROM erp_b
WHERE row_kind = 'journal line'
  AND (posting_date_p BETWEEN getvariable('q_start') - getvariable('boundary_days')
                          AND getvariable('q_start') + getvariable('boundary_days')
    OR posting_date_p BETWEEN getvariable('q_end') - getvariable('boundary_days')
                          AND getvariable('q_end') + getvariable('boundary_days'))
ORDER BY posting_date_p, excel_row;

-- name: outside_quarter_summary
-- LocalAccount = '(all)' is the total for that side of the quarter.
SELECT
    CASE WHEN posting_date_p < getvariable('q_start') THEN 'before Q3' ELSE 'after Q3' END AS vs_quarter,
    coalesce(LocalAccount, '(all)') AS LocalAccount,
    count(*)            AS journal_lines,
    min(posting_date_p) AS min_date,
    max(posting_date_p) AS max_date,
    sum(amount_cad_n)   AS journal_cad
FROM erp_b
WHERE row_kind = 'journal line'
  AND posting_date_p NOT BETWEEN getvariable('q_start') AND getvariable('q_end')
GROUP BY GROUPING SETS ((vs_quarter, LocalAccount), (vs_quarter))
ORDER BY vs_quarter, LocalAccount;


-- ---------------------------------------------------------------------------
-- 5. Duplicates
-- ---------------------------------------------------------------------------

-- name: dup_exact
-- Journal lines identical in all six columns.
SELECT JournalID, PostingDate, LocalAccount, Description, AmountCAD, Source,
       count(*) AS copies, list(excel_row ORDER BY excel_row) AS excel_rows
FROM erp_b
WHERE row_kind = 'journal line'
GROUP BY ALL
HAVING count(*) > 1
ORDER BY JournalID;

-- name: dup_journalid
-- JournalIDs used on more than one journal line, and whether the lines differ.
SELECT
    JournalID,
    count(*)                                                       AS rows,
    count(DISTINCT (PostingDate, LocalAccount, Description, AmountCAD, Source)) AS content_variants,
    list(excel_row ORDER BY excel_row)                             AS excel_rows,
    list(LocalAccount ORDER BY excel_row)                          AS accounts,
    list(PostingDate ORDER BY excel_row)                           AS dates,
    list(AmountCAD ORDER BY excel_row)                             AS amounts
FROM erp_b
WHERE row_kind = 'journal line'
GROUP BY JournalID
HAVING count(*) > 1
ORDER BY JournalID;

-- name: dup_content_other_journalid
-- Same date, account, description, amount and source under different JournalIDs.
SELECT
    PostingDate, LocalAccount, Description, AmountCAD, Source,
    count(*)                              AS rows,
    list(JournalID ORDER BY excel_row)    AS journal_ids,
    list(excel_row ORDER BY excel_row)    AS excel_rows
FROM erp_b
WHERE row_kind = 'journal line'
GROUP BY ALL
HAVING count(DISTINCT JournalID) > 1
ORDER BY ALL;


-- ---------------------------------------------------------------------------
-- 6. Negative amounts
-- ---------------------------------------------------------------------------

-- name: negative_summary
SELECT
    LocalAccount,
    strftime(posting_date_p, '%Y-%m') AS posting_month,
    count(*)                          AS negative_lines,
    sum(amount_cad_n)                 AS negative_cad
FROM erp_b
WHERE row_kind = 'journal line' AND amount_cad_n < 0
GROUP BY ALL
ORDER BY ALL;

-- name: negative_rows
-- Every negative journal line, with any same-account line of the opposite amount.
SELECT
    n.excel_row, n.JournalID, n.PostingDate, n.LocalAccount, n.Description, n.AmountCAD, n.Source,
    count(o.excel_row)                    AS opposite_amount_lines,
    list(o.JournalID ORDER BY o.excel_row) AS opposite_journal_ids,
    list(o.PostingDate ORDER BY o.excel_row) AS opposite_dates
FROM erp_b AS n
LEFT JOIN erp_b AS o
       ON o.row_kind = 'journal line' AND o.LocalAccount = n.LocalAccount
      AND o.amount_cad_n = -n.amount_cad_n
WHERE n.row_kind = 'journal line' AND n.amount_cad_n < 0
GROUP BY ALL
ORDER BY n.excel_row;


-- ---------------------------------------------------------------------------
-- 7. Local accounts vs account_map and the 73xx-RM pattern
-- ---------------------------------------------------------------------------

-- name: localaccount_vs_map
-- Each local account on journal lines: is it in account_map, what does the map
-- say, and does the code itself look like 73xx-RM? (Facts only; README rule 6
-- says every local account in the 73xx-RM range is R&M.)
WITH gl AS (
    SELECT
        LocalAccount,
        count(*)                                                    AS journal_lines,
        sum(amount_cad_n)                                           AS all_dates_cad,
        sum(amount_cad_n) FILTER (WHERE posting_date_p BETWEEN getvariable('q_start') AND getvariable('q_end')) AS q3_cad
    FROM erp_b
    WHERE row_kind = 'journal line'
    GROUP BY LocalAccount
)
SELECT
    gl.LocalAccount,
    gl.journal_lines,
    gl.all_dates_cad,
    gl.q3_cad,
    m.LocalAccount IS NOT NULL                              AS in_account_map,
    m.GroupAccount                                          AS map_group_account,
    m.GroupDescription                                      AS map_group_description,
    regexp_full_match(gl.LocalAccount, '73[0-9]{2}-.*')     AS code_starts_73xx,
    regexp_matches(gl.LocalAccount, '^73[0-9]{2}-RM(-|$)')  AS code_is_73xx_rm
FROM gl
LEFT JOIN account_map_raw AS m ON m.LocalAccount = gl.LocalAccount
ORDER BY gl.LocalAccount;

-- name: map_accounts_not_in_gl
SELECT m.*
FROM account_map_raw AS m
WHERE m.LocalAccount NOT IN (SELECT LocalAccount FROM erp_b WHERE row_kind = 'journal line')
ORDER BY m.LocalAccount;
