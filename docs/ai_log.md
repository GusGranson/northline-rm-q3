# AI Usage Log — Northline Q3 R&M Exercise

Running log for Part 5. Append entries as they happen; don't reconstruct after the fact.

**For agents working in this repo:** when the human corrects something you proposed or produced, or you catch your own mistake, add an entry under *Corrections* using the template below. Add notably effective prompts under *Prompts*. Don't edit or remove existing entries.

---

## Tools

| Tool | Used for |
|---|---|
| Claude (chat) | Planning, strategy, reviewing findings, drafting write-ups |
| Claude Code | Profiling, building the pipeline, verification runs |

---

## Corrections

<!-- Template:
### C-NN · YYYY-MM-DD · <short title>
- **Tool / stage:**
- **What the AI got wrong:**
- **How it was caught:**
- **Fix applied:**
- **Why it matters:**
-->

### C-01 · 2026-10-15 · Finance rules duplicated in agent instructions
- **Tool / stage:** Claude (chat) · planning
- **What the AI got wrong:** Proposed putting the README Finance rules both in `CLAUDE.md` and in a config file.
- **How it was caught:** Human review of the plan. The rules are deterministic logic and belong only in the code/config layer, not in agent instructions.
- **Fix applied:** Single source of truth. Rule values live only in `config/` and are read by the SQL. `CLAUDE.md` holds only agent instructions (stage gates, conventions, guardrails) and pointers to the spec and the config.
- **Why it matters:** Two copies of the same rules drift over time. That is the exact governance failure the exercise is about: rule ownership and a single definition of R&M.

### C-02 · 2026-10-15 · Lenient amount parse would have silently dropped ERP-B amounts
- **Tool / stage:** Claude Code · profiling
- **What the AI got wrong:** The first ERP-B profiling view parsed AmountCAD with `TRY_CAST(... AS DECIMAL)`. 18 cells are text with thousands separators (`'4,581.93'`, CAD 51,965.23, all on 73xx-RM accounts). Those would have become NULL and fallen out of every sum without an error.
- **How it was caught:** A separate typed read of the sheet failed on cell E291. The column profile then showed 1,486 of 1,504 amounts parsing. Listing every non-plain amount found the 18 text cells.
- **Fix applied:** The profiling lens strips commas before casting and is labelled as a lens. `amount_text_shapes` and `amount_nonplain_rows` list the cells. The subtotal tie-out (`subtotal_check`, 0.00 on all 31) confirms they are real amounts. How the build treats them is left to the human (findings Q-6).
- **Why it matters:** `TRY_CAST` turns a format defect into a silent understatement of R&M. The build needs a row-level check that every amount parsed, not just that the query ran.

### C-03 · 2026-10-15 · JE register total mixed CAD and USD
- **Tool / stage:** Claude Code · profiling
- **What the AI got wrong:** `totals_by_account` in the JE register profile had an "ALL" row that added the CA entry (JE-0927, CAD 3,302.00) to the six USD entries, giving 27,842.83.
- **How it was caught:** Self-review of the result before writing findings. The CA row's local account and "Fuel – CAD" description show it is not USD.
- **Fix applied:** Totals are now per entity only (US USD 24,540.83; CA CAD 3,302.00), with a comment saying why there is no all-entity total.
- **Why it matters:** A mixed-currency total would carry straight into the bridge as a wrong reconciling amount.

### C-04 · 2026-10-15 · Bridge crashed instead of failing its residual check
- **Tool / stage:** Claude Code · bridge
- **What the AI got wrong:** `sql/09_bridge.sql` assumed the config table of Accounting's FX overrides always exists. With no override listed, which legitimately means "Accounting used Finance's rate every month", the build stopped with a missing-table error instead of reporting a non-zero residual.
- **How it was caught:** A deliberate failure test: rerunning the build against a scratch config without the September override, expecting check C25 to fail with an 11,681.61 residual.
- **Fix applied:** The bridge SQL now starts from an empty override table when none is configured. The same test then failed cleanly on C25 (residual 11,681.61, only `checks.csv` written), and the real build passes all 27 checks.
- **Why it matters:** A check proves nothing until it has been seen to fail. A crash says "something broke"; a failed C25 says "the bridge doesn't close, by this much".

---

## Prompts

<!-- Add the instructions that worked best, verbatim or lightly trimmed, with one line on why. -->

---

## Verification approach

<!-- How AI output was checked: assertions, blind independent rerun, adversarial review. Fill in as built. -->

### V-01 · 2026-10-15 · Blind independent rebuild matches the pipeline to the cent
- **Tool / stage:** Claude (Sonnet) as the independent builder; Claude Code (Opus) ran the comparison · verify
- **What was checked:** `output/rm_q3_by_branch.csv` from the pipeline (commit `3b72320`).
- **Method:**
  - A separate Sonnet session rebuilt Part 1 from the raw data files, the README and `docs/decisions.md` only. It had no access to our code, config, outputs or profiling findings.
  - Its build, `verify/build_rm_q3.py`, uses Python, `Decimal` and openpyxl, with no DuckDB, so every parser and the decimal library differ from the pipeline's.
  - Its script was rerun on a copy of its inputs and reproduced its CSV byte for byte.
  - The two CSVs were then compared cell by cell in plain Python.
  - Its script was also read line by line for differences its notes don't mention.
- **Result:** 39 of 39 cells identical: 13 rows, same order, both totalling USD 14,090,228.96. The files differ only in line endings (CRLF vs LF).
- **Its calls:** `verify_notes.md` lists six calls, not three. Three are genuinely undocumented: ExtCost used as given, the exact 73xx-RM pattern, and the sort order. The other three restate decisions or scope. All six agree with the pipeline.
- **Its script:** Reading it found five places where its checks are narrower than ours, including a D-02 check on the kept copy rather than the first appearance. None changes a number here.
- **Limits:**
  - Both builds were given the same decisions, so the match tests the implementation, not the treatments.
  - The bridge to Accounting is not covered.
- **Details:** `verify/comparison.md`.

---

## AI-written code estimate

<!-- Fill in at the end. -->
