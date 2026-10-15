-- =============================================================================
-- 07 · Data quality log (Part 2)
-- One row per data quality rule: what the issue is, how it is detected, the
-- treatment, and the rows and amount affected.
--   rows/amount: bucket rules count their bucket (D-10); other rules count the
--   rows named in `scope`.
--   usd_affected: ERP-A amounts are USD. ERP-B amounts are translated month by
--   month at that month's rate and rounded to cents. A month with no rate in the
--   pack is not translated: its CAD goes to cad_without_rate and usd_note says
--   so (D-11).
-- =============================================================================

CREATE TABLE dq_rules (
    dq_id        VARCHAR,
    finding_ref  VARCHAR,   -- profiling/findings.md
    source       VARCHAR,
    scope        VARCHAR,
    issue        VARCHAR,
    detection    VARCHAR,
    treatment    VARCHAR,
    decision_ref VARCHAR
);

INSERT INTO dq_rules VALUES
('A01', 'A-1', 'ERP-A', 'bucket',
 'Line exported more than once (a later export re-pulled an earlier one)',
 'Same line key (erp_a_dedupe_key) in more than one export',
 'Keep the copy from the latest export, drop the others', 'D-01'),
('A02', 'A-2', 'ERP-A', 'all rows',
 'Line in an export pulled after the README''s last export of the quarter',
 'ExportedAt later than erp_a_last_export_cutoff',
 'None: TransDate decides the period. Check C08 confirms no Q3 line arrived late', 'D-02'),
('A03', 'A-3', 'ERP-A', 'bucket',
 'Line dated outside Q3',
 'TransDate outside period_start..period_end',
 'Excluded (README rule 3)', 'README 3'),
('A04', 'A-4', 'ERP-A', 'all rows',
 'TransDate typed as MM/DD/YYYY instead of YYYY-MM-DD',
 'TransDate does not parse in the first configured format',
 'Parsed as MM/DD/YYYY (no value has a first part above 12)', 'D-03'),
('A05', 'A-4', 'ERP-A', 'all rows',
 'MM/DD/YYYY TransDate that also reads as a different valid date as DD/MM/YYYY',
 'Both readings parse and give different dates',
 'Read as MM/DD/YYYY on the evidence of the whole column', 'D-03'),
('A06', 'A-5', 'ERP-A', 'all rows',
 'Whse not typed as its branch code (case, spaces or full name)',
 'Raw Whse differs from the branch it maps to',
 'Mapped with the explicit Whse table; unmapped values fail the build', 'D-04'),
('A07', 'A-6', 'ERP-A', 'all rows',
 'Acct with a leading space or a trailing .0',
 'Raw Acct differs from the parsed integer account',
 'Trimmed and read as an integer; unknown accounts fail the build', 'D-09'),
('A08', 'A-7', 'ERP-A', 'kept rows',
 'Activity under a closed branch dated on or after its close',
 'Branch has a reassignment in cfg_branches_reassign and TransDate is on or after effective_from',
 'Reported under the receiving branch in cfg_branches_reassign (README rule 4)', 'README 4'),
('A09', 'A-8', 'ERP-A', 'bucket',
 'Capitalised rebuild operations on R&M accounts',
 'Oper in rm_capitalised_operations',
 'Excluded from R&M (README rule 2)', 'README 2'),
('A10', 'A-9', 'ERP-A', 'kept rows',
 'Reversal lines (negative Qty), each on its own Line number',
 'Qty below zero',
 'Counted in the month of its own date (README rule 3)', 'README 3'),
('A11', 'A-10', 'ERP-A', 'kept rows',
 'Customer number on R&M-account lines',
 'CustNum present',
 'None: the account decides (README rule 1)', 'README 1'),
('A12', '-', 'ERP-A', 'all rows',
 'ExtCost differs from Qty x UnitCost',
 'ExtCost <> round(Qty x UnitCost, 2)',
 'Control: none expected', '-'),
('B01', 'B-1', 'ERP-B', 'bucket',
 'SUBTOTAL rows mixed in with journal lines',
 'JournalID equals erp_b_subtotal_marker',
 'Excluded; each must tie to its account-month journal lines (check C13)', 'D-06'),
('B02', 'B-2', 'ERP-B', 'all rows',
 'Amount stored as text with a thousands separator',
 'Raw amount contains erp_b_thousands_separator',
 'Separator stripped, read as a number', 'D-06'),
('B03', 'B-3', 'ERP-B', 'all rows',
 'Amount with binary-float tail (more than 2 decimals)',
 'Raw amount has 3 or more decimals',
 'Rounded to cents at staging; check C12 bounds the change', 'D-07'),
('B04', 'B-4', 'ERP-B', 'journal lines',
 'PostingDate stored as DD/MM/YYYY text, not as dates',
 'Every journal line',
 'Parsed as DD/MM/YYYY', 'D-03'),
('B05', 'B-4', 'ERP-B', 'journal lines',
 'DD/MM/YYYY PostingDate that also reads as a different valid date as MM/DD/YYYY',
 'Both readings parse and give different dates',
 'Read as DD/MM/YYYY on the evidence of the whole column', 'D-03'),
('B06', 'B-5', 'ERP-B', 'bucket',
 'Line posted outside Q3',
 'PostingDate outside period_start..period_end',
 'Excluded (README rule 3)', 'README 3'),
('B07', 'B-6', 'ERP-B', 'kept rows',
 'Local account in the 73xx-RM range missing from account_map',
 'Kept local account not found in account_map',
 'Included as R&M (README rule 6); Accounting to add it to the map', 'D-05'),
('B08', 'B-7', 'ERP-B', 'kept rows',
 'Credit lines (negative amount)',
 'AmountCAD below zero',
 'Counted in the month of its own date (README rule 3)', 'README 3'),
('B09', '-', 'ERP-B', 'journal lines',
 'JournalID used on more than one journal line',
 'JournalID repeated',
 'Control: none expected', '-');

-- Every affected line, with the month it falls in and its native amount.
CREATE TABLE dq_affected AS
SELECT 'A01' AS dq_id, period_month, ext_cost_usd AS amount FROM erp_a_lines WHERE bucket = 'duplicate_copy'
UNION ALL
SELECT 'A02', period_month, ext_cost_usd FROM erp_a_lines WHERE exported_at > getvariable('erp_a_last_export_cutoff')
UNION ALL
SELECT 'A03', period_month, ext_cost_usd FROM erp_a_lines WHERE bucket = 'outside_period'
UNION ALL
SELECT 'A04', period_month, ext_cost_usd FROM erp_a_lines
WHERE TRY_STRPTIME(trans_date_raw, getvariable('erp_a_date_formats')[1]) IS NULL
UNION ALL
SELECT 'A05', period_month, ext_cost_usd FROM erp_a_lines
WHERE TRY_STRPTIME(trans_date_raw, getvariable('erp_a_date_formats')[1]) IS NULL
  AND TRY_STRPTIME(trans_date_raw, '%d/%m/%Y')::DATE <> trans_date   -- the rejected reading
UNION ALL
SELECT 'A06', period_month, ext_cost_usd FROM erp_a_lines WHERE whse_raw <> branch
UNION ALL
SELECT 'A07', period_month, ext_cost_usd FROM erp_a_lines WHERE acct_raw <> CAST(acct AS VARCHAR)
UNION ALL
SELECT 'A08', period_month, ext_cost_usd FROM erp_a_lines WHERE bucket = 'kept' AND report_branch <> branch
UNION ALL
SELECT 'A09', period_month, ext_cost_usd FROM erp_a_lines WHERE bucket = 'capitalised_operation'
UNION ALL
SELECT 'A10', period_month, ext_cost_usd FROM erp_a_lines WHERE bucket = 'kept' AND qty < 0
UNION ALL
SELECT 'A11', period_month, ext_cost_usd FROM erp_a_lines WHERE bucket = 'kept' AND cust_num IS NOT NULL
UNION ALL
SELECT 'A12', period_month, ext_cost_usd FROM erp_a_lines
WHERE ext_cost_usd <> round(qty * unit_cost, getvariable('rounding_decimals'))
UNION ALL
SELECT 'B01', period_month, amount_cad FROM erp_b_lines WHERE bucket = 'subtotal_row'
UNION ALL
SELECT 'B02', period_month, amount_cad FROM erp_b_lines
WHERE contains(amount_raw, getvariable('erp_b_thousands_separator'))
UNION ALL
SELECT 'B03', period_month, amount_cad FROM erp_b_lines WHERE regexp_matches(amount_raw, '\.[0-9]{3,}$')
UNION ALL
SELECT 'B04', period_month, amount_cad FROM erp_b_lines WHERE row_type = 'journal'
UNION ALL
SELECT 'B05', period_month, amount_cad FROM erp_b_lines
WHERE row_type = 'journal'
  AND TRY_STRPTIME(posting_date_raw, '%m/%d/%Y')::DATE <> posting_date   -- the rejected reading
UNION ALL
SELECT 'B06', period_month, amount_cad FROM erp_b_lines WHERE bucket = 'outside_period'
UNION ALL
SELECT 'B07', period_month, amount_cad FROM erp_b_lines
WHERE bucket = 'kept' AND local_account NOT IN (SELECT local_account FROM stg_account_map)
UNION ALL
SELECT 'B08', period_month, amount_cad FROM erp_b_lines WHERE bucket = 'kept' AND amount_cad < 0
UNION ALL
SELECT 'B09', period_month, amount_cad FROM erp_b_lines
WHERE row_type = 'journal'
  AND journal_id IN (SELECT journal_id FROM erp_b_lines WHERE row_type = 'journal' GROUP BY 1 HAVING count(*) > 1);

CREATE TABLE dq_log AS
WITH by_month AS (
    SELECT dq_id, period_month, count(*) AS rows, sum(amount) AS amount
    FROM dq_affected
    GROUP BY ALL
),
translated AS (
    SELECT
        m.*,
        CASE WHEN r.source = 'ERP-A' THEN m.amount
             ELSE round(m.amount * fx.rate, getvariable('rounding_decimals'))
        END AS usd   -- NULL for an ERP-B month with no rate (D-11)
    FROM by_month AS m
    JOIN dq_rules AS r USING (dq_id)
    LEFT JOIN stg_fx AS fx ON fx.month = m.period_month
)
SELECT
    r.dq_id,
    r.finding_ref,
    r.source,
    r.issue,
    r.detection,
    r.treatment,
    r.decision_ref,
    r.scope,
    coalesce(sum(t.rows), 0)                                          AS rows_affected,
    coalesce(sum(t.amount), 0)                                        AS amount_native,
    CASE WHEN r.source = 'ERP-A' THEN getvariable('erp_a_currency')
         ELSE getvariable('erp_b_currency') END                       AS currency,
    CASE WHEN count(t.dq_id) = 0 THEN 0 ELSE sum(t.usd) END           AS usd_affected,
    coalesce(sum(t.amount) FILTER (WHERE t.usd IS NULL), 0)           AS cad_without_rate,
    CASE WHEN count(*) FILTER (WHERE t.usd IS NULL) > 0 THEN
        'No CAD/USD rate in the data pack for '
        || string_agg(t.period_month, ', ' ORDER BY t.period_month) FILTER (WHERE t.usd IS NULL)
        || '; that CAD is in cad_without_rate and not translated (D-11)'
    END                                                               AS usd_note
FROM dq_rules AS r
LEFT JOIN translated AS t USING (dq_id)
GROUP BY ALL
ORDER BY r.dq_id;
