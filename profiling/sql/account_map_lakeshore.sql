-- =============================================================================
-- Profile: data/raw/account_map_lakeshore.csv
-- Lakeshore local account -> Northline group account. Maintained by Accounting.
--
-- Read-only. Each `-- name:` query is saved by run_profiling.py to
-- profiling/results/account_map_lakeshore/NN_<name>.csv.
-- The check of GL local accounts against this map is in
-- erp_b_lakeshore_gl_detail.sql (query localaccount_vs_map).
-- =============================================================================

CREATE TABLE account_map_raw AS
SELECT *
FROM read_csv('data/raw/account_map_lakeshore.csv', header = true, all_varchar = true);

-- name: row_count
SELECT
    count(*)                         AS data_rows,
    count(DISTINCT LocalAccount)     AS distinct_local_accounts,
    count(DISTINCT GroupAccount)     AS distinct_group_accounts
FROM account_map_raw;

-- name: column_types_inferred
SELECT column_name, column_type AS inferred_type
FROM (DESCRIBE SELECT * FROM read_csv('data/raw/account_map_lakeshore.csv'));

-- name: contents
-- Every row, with facts about the local account code itself.
SELECT
    rowid + 2                                                AS file_line,
    '[' || LocalAccount || ']'                               AS local_account_raw,
    GroupAccount,
    GroupDescription,
    regexp_full_match(LocalAccount, '73[0-9]{2}-.*')         AS code_starts_73xx,
    regexp_matches(LocalAccount, '^73[0-9]{2}-RM(-|$)')      AS code_is_73xx_rm
FROM account_map_raw
ORDER BY file_line;

-- name: duplicates
-- Local accounts mapped more than once, and group accounts with several local accounts.
SELECT 'LocalAccount' AS key_column, LocalAccount AS key_value, count(*) AS rows,
       list(GroupAccount ORDER BY GroupAccount) AS mapped_to
FROM account_map_raw GROUP BY LocalAccount HAVING count(*) > 1
UNION ALL
SELECT 'GroupAccount', GroupAccount, count(*), list(LocalAccount ORDER BY LocalAccount)
FROM account_map_raw GROUP BY GroupAccount HAVING count(*) > 1
ORDER BY key_column, key_value;
