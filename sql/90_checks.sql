-- =============================================================================
-- 90 · Checks
-- One row per assertion. run.py fails the build (exit 1) if any is false and
-- then writes only output/checks.csv. `detail` shows what was counted.
-- =============================================================================

CREATE TABLE checks (
    check_id     VARCHAR,
    description  VARCHAR,
    ref          VARCHAR,
    passed       BOOLEAN,
    detail       VARCHAR
);

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C00', 'Config: dedupe_keep and rounding mode are supported values; Whse map and reassignments have unique keys',
       'D-01, D-04, D-07',
       getvariable('erp_a_dedupe_keep') IN ('latest', 'earliest')
       AND getvariable('rounding_mode') = 'half_up'
       AND (SELECT count(*) = count(DISTINCT raw) FROM cfg_erp_a_whse_map)
       AND (SELECT count(*) = count(DISTINCT from_branch) FROM cfg_branches_reassign),
       'dedupe_keep=' || getvariable('erp_a_dedupe_keep') || ', rounding_mode=' || getvariable('rounding_mode');

-- ---------------------------------------------------------------------------
-- ERP-A staging
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C01', 'ERP-A: every TransDate parses in a configured format', 'D-03',
       count(*) = 0, count(*) || ' rows fail'
FROM stg_erp_a WHERE trans_date IS NULL;

INSERT INTO checks
SELECT 'C02', 'ERP-A: every raw Whse value is in the Whse map', 'D-04',
       count(*) = 0, count(*) || ' rows unmapped: ' || coalesce(string_agg(DISTINCT '[' || whse_raw || ']', ' '), 'none')
FROM stg_erp_a WHERE branch IS NULL;

INSERT INTO checks
SELECT 'C03', 'ERP-A: every Acct is a README group account', 'D-09',
       count(*) = 0, count(*) || ' rows fail'
FROM stg_erp_a WHERE acct IS NULL OR NOT list_contains(getvariable('chart_group_accounts'), acct);

INSERT INTO checks
SELECT 'C04', 'ERP-A: Line, Oper, Qty, UnitCost, ExtCost and ExportedAt all parse', 'D-07',
       count(*) = 0, count(*) || ' rows fail'
FROM stg_erp_a
WHERE line IS NULL OR oper IS NULL OR qty IS NULL OR unit_cost IS NULL OR ext_cost_usd IS NULL OR exported_at IS NULL;

INSERT INTO checks
SELECT 'C05', 'ERP-A: casting UnitCost and ExtCost to cents removes only float noise', 'D-07',
       count(*) = 0, count(*) || ' rows changed by more than ' || getvariable('rounding_cast_noise_tolerance')
FROM stg_erp_a
WHERE abs(TRY_CAST(ext_cost_raw AS DECIMAL(38, 12)) - ext_cost_usd) > getvariable('rounding_cast_noise_tolerance')
   OR abs(TRY_CAST(unit_cost_raw AS DECIMAL(38, 12)) - unit_cost) > getvariable('rounding_cast_noise_tolerance');

INSERT INTO checks
SELECT 'C06', 'ERP-A: line key is complete and unique within every export', 'D-01',
       (SELECT count(*) FROM stg_erp_a WHERE line_key_nulls > 0) = 0 AND count(*) = 0,
       count(*) || ' key repeats within an export'
FROM (SELECT exported_at, line_key FROM stg_erp_a GROUP BY ALL HAVING count(*) > 1);

INSERT INTO checks
SELECT 'C07', 'ERP-A: line key is unique after de-duplication', 'D-01',
       count(*) = 0, count(*) || ' keys kept more than once'
FROM (SELECT line_key FROM erp_a_lines WHERE bucket <> 'duplicate_copy' GROUP BY 1 HAVING count(*) > 1);

INSERT INTO checks
SELECT 'C08', 'ERP-A: no Q3-dated line first appears in an export after the cut-off', 'D-02',
       count(*) = 0, count(*) || ' late Q3 lines'
FROM (
    SELECT line_key
    FROM stg_erp_a
    GROUP BY line_key
    HAVING min(exported_at) > getvariable('erp_a_last_export_cutoff')
       AND bool_or(trans_date BETWEEN getvariable('period_start') AND getvariable('period_end'))
);

INSERT INTO checks
SELECT 'C09', 'ERP-A: no kept line reports under a branch on or after its close date', 'README 4, D-12',
       count(*) = 0, count(*) || ' rows'
FROM erp_a_lines AS a
JOIN cfg_branches_reassign AS ra
  ON a.report_branch = ra.from_branch AND a.trans_date >= ra.effective_from
WHERE a.bucket = 'kept';

-- ---------------------------------------------------------------------------
-- ERP-B staging
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C10', 'ERP-B: every row is a journal line or a SUBTOTAL row', 'D-06',
       count(*) = 0, count(*) || ' unrecognised rows'
FROM stg_erp_b WHERE row_type IS NULL;

INSERT INTO checks
SELECT 'C11', 'ERP-B: every PostingDate parses in a configured format', 'D-03',
       count(*) = 0, count(*) || ' rows fail'
FROM stg_erp_b WHERE posting_date IS NULL;

INSERT INTO checks
SELECT 'C12', 'ERP-B: every amount parses, and casting to cents removes only float noise', 'D-06, D-07',
       count(*) = 0, count(*) || ' rows fail'
FROM stg_erp_b
WHERE amount_cad IS NULL
   OR abs(TRY_CAST(replace(amount_raw, getvariable('erp_b_thousands_separator'), '') AS DECIMAL(38, 12)) - amount_cad)
      > getvariable('rounding_cast_noise_tolerance');

INSERT INTO checks
SELECT 'C13', 'ERP-B: every SUBTOTAL equals the journal lines of its account and month', 'D-06',
       count(*) = 0 AND (SELECT count(*) FROM stg_erp_b WHERE row_type = 'subtotal') > 0,
       count(*) || ' subtotals do not tie'
FROM (
    SELECT s.source_row
    FROM stg_erp_b AS s
    LEFT JOIN (
        SELECT local_account, strftime(posting_date, '%Y-%m') AS month, sum(amount_cad) AS cad
        FROM stg_erp_b WHERE row_type = 'journal' GROUP BY ALL
    ) AS j
      ON j.local_account = s.local_account AND j.month = strftime(s.posting_date, '%Y-%m')
    WHERE s.row_type = 'subtotal'
      AND s.amount_cad IS DISTINCT FROM j.cad
);

INSERT INTO checks
SELECT 'C14', 'Account map: for every mapped account, the 73xx-RM range and the map agree on R&M', 'D-05',
       count(*) = 0, count(*) || ' disagreements'
FROM stg_account_map
WHERE regexp_matches(local_account, getvariable('erp_b_rm_local_account_pattern'))
      IS DISTINCT FROM list_contains(getvariable('rm_group_accounts'), group_account);

-- ---------------------------------------------------------------------------
-- FX and rounding
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C15', 'FX: one exact rate for every month with kept Lakeshore lines', 'README 5, D-07',
       count(*) = 0, count(*) || ' months without a usable rate'
FROM lks_month_cad AS l
LEFT JOIN (SELECT month, count(*) AS n, any_value(rate) AS rate, any_value(rate_raw) AS rate_raw
           FROM stg_fx GROUP BY month) AS fx USING (month)
WHERE fx.n IS DISTINCT FROM 1
   OR fx.rate IS NULL
   OR TRY_CAST(fx.rate_raw AS DECIMAL(38, 12)) <> fx.rate;

INSERT INTO checks
SELECT 'C16', 'Rounding: translated Lakeshore month totals are positive, so ROUND (half away from zero) is half-up', 'D-07',
       count(*) = 0, count(*) || ' non-positive months'
FROM lks_month_cad WHERE cad <= 0;

-- ---------------------------------------------------------------------------
-- Row conservation (CLAUDE.md required check)
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C17', 'ERP-A: every line of the file is parsed as a row', 'CLAUDE.md',
       file_lines = raw_rows, file_lines || ' data lines in file, ' || raw_rows || ' rows read'
FROM (
    SELECT
        (SELECT count(*) - 1 FROM (SELECT unnest(string_split(content, chr(10))) AS l FROM read_text(getvariable('sources_erp_a')))
         WHERE trim(l, chr(13) || ' ') <> '')                                                       AS file_lines,
        (SELECT count(*) FROM raw_erp_a)                                                            AS raw_rows
);

INSERT INTO checks
SELECT 'C18', 'Row conservation: raw rows = sum of buckets, per source', 'CLAUDE.md, D-10',
       bool_and(raw_rows = bucket_rows),
       string_agg(source || ' raw ' || raw_rows || ' = buckets ' || bucket_rows, '; ' ORDER BY source)
FROM (
    SELECT source,
           sum(rows) FILTER (WHERE bucket = 'raw')  AS raw_rows,
           sum(rows) FILTER (WHERE bucket <> 'raw') AS bucket_rows
    FROM row_conservation GROUP BY source
);

INSERT INTO checks
SELECT 'C19', 'Amount conservation: raw amount = sum of bucket amounts, per source', 'CLAUDE.md, D-10',
       bool_and(raw_amount = bucket_amount),
       string_agg(source || ' raw ' || raw_amount || ' = buckets ' || bucket_amount, '; ' ORDER BY source)
FROM (
    SELECT source,
           sum(amount_native) FILTER (WHERE bucket = 'raw')  AS raw_amount,
           sum(amount_native) FILTER (WHERE bucket <> 'raw') AS bucket_amount
    FROM row_conservation GROUP BY source
);

-- ---------------------------------------------------------------------------
-- Data quality log (CLAUDE.md required check)
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C20', 'DQ log: every rule reports rows and USD (blank USD only with a reason)', 'CLAUDE.md, D-11',
       count(*) = 0, count(*) || ' rules incomplete'
FROM dq_log
WHERE rows_affected IS NULL
   OR amount_native IS NULL
   OR (usd_affected IS NULL AND usd_note IS NULL)
   OR (cad_without_rate <> 0 AND usd_note IS NULL);

-- ---------------------------------------------------------------------------
-- Output file format (CLAUDE.md required check; exercise.pdf Part 1)
-- run.py also reads the written file back and requires it to match this table.
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C21', 'Output: columns are exactly ' || array_to_string(getvariable('output_format_rm_q3_by_branch_columns'), ', '),
       'CLAUDE.md',
       list(column_name ORDER BY ordinal_position) = getvariable('output_format_rm_q3_by_branch_columns'),
       array_to_string(list(column_name ORDER BY ordinal_position), ', ')
FROM information_schema.columns
WHERE table_name = 'rm_q3_by_branch';

INSERT INTO checks
SELECT 'C22', 'Output: Branch is a branch code, Month is YYYY-MM in Q3, RM_USD has 2 decimals and no symbols',
       'CLAUDE.md',
       count(*) FILTER (
           WHERE NOT list_contains(getvariable('branches_codes'), Branch)
              OR NOT regexp_full_match(Month, '[0-9]{4}-[0-9]{2}')
              OR TRY_STRPTIME(Month || '-01', '%Y-%m-%d')::DATE NOT BETWEEN getvariable('period_start') AND getvariable('period_end')
              OR NOT regexp_full_match(RM_USD, '-?[0-9]+\.[0-9]{2}')
       ) = 0 AND count(*) > 0,
       count(*) || ' rows'
FROM rm_q3_by_branch;

INSERT INTO checks
SELECT 'C23', 'Output: one row per branch and month', 'CLAUDE.md',
       count(*) = count(DISTINCT (Branch, Month)), count(*) || ' rows, ' || count(DISTINCT (Branch, Month)) || ' distinct'
FROM rm_q3_by_branch;

INSERT INTO checks
SELECT 'C24', 'Output: total equals kept ERP-A lines plus translated Lakeshore months', 'README 5, 8',
       out_total = expected_total, 'output ' || out_total || ', lines ' || expected_total
FROM (
    SELECT
        (SELECT sum(RM_USD::DECIMAL(18, 2)) FROM rm_q3_by_branch) AS out_total,
        (SELECT sum(ext_cost_usd) FROM erp_a_lines WHERE bucket = 'kept')
          + (SELECT sum(round(l.cad * fx.rate, getvariable('rounding_decimals')))
             FROM lks_month_cad AS l JOIN stg_fx AS fx USING (month))   AS expected_total
);

-- ---------------------------------------------------------------------------
-- Bridge to Accounting (CLAUDE.md required check; exercise.pdf Part 3)
-- ---------------------------------------------------------------------------

INSERT INTO checks
SELECT 'C25', 'Bridge: residual to Accounting''s reported total is exactly 0.00', 'CLAUDE.md, Part 3',
       coalesce(amount_usd = 0, false), 'residual ' || coalesce(amount_usd::VARCHAR, 'not computed')
FROM bridge
WHERE line_type = 'residual';

INSERT INTO checks
SELECT 'C26', 'Bridge: one Accounting total for the period, and every item traces to a JE or an FX month (no plugs)',
       'CLAUDE.md, Part 3',
       (SELECT count(*) FROM stg_accounting_close
         WHERE period = strftime(getvariable('period_start'), '%Y') || '-Q' || quarter(getvariable('period_start'))
           AND usd IS NOT NULL) = 1
       AND count(*) FILTER (WHERE amount_usd IS NULL
                               OR (item_type = 'JE' AND source_ref NOT IN (SELECT je_id FROM stg_je))
                               OR (item_type = 'FX' AND source_ref NOT IN (SELECT month FROM stg_fx))) = 0,
       count(*) || ' items'
FROM bridge_items;
