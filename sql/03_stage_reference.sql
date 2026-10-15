-- =============================================================================
-- 03 · Stage reference data: FX rates and the Lakeshore account map
-- =============================================================================

-- FX: one CAD->USD rate per month, of the type README rule 5 names
-- (config fx_rate_column). Rates stay DECIMAL (D-07).
CREATE TABLE raw_fx AS
SELECT *
FROM read_csv(getvariable('sources_fx'), header = true, all_varchar = true);

CREATE TABLE stg_fx AS
SELECT
    Month                            AS month,
    rate_raw,
    TRY_CAST(rate_raw AS DECIMAL(18, 8)) AS rate
FROM raw_fx
UNPIVOT (rate_raw FOR rate_column IN (COLUMNS(* EXCLUDE (Month))))
WHERE rate_column = getvariable('fx_rate_column');

-- Account map, maintained by Accounting. Used for checks and the DQ log
-- only: README rule 6 (the 73xx-RM range) decides what is R&M (D-05).
CREATE TABLE stg_account_map AS
SELECT
    LocalAccount                       AS local_account,
    TRY_CAST(GroupAccount AS INTEGER)  AS group_account,
    GroupDescription                   AS group_description
FROM read_csv(getvariable('sources_account_map'), header = true, all_varchar = true);
