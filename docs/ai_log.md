# AI Usage Log — Northline Q3 R&M Exercise

Running log for Part 5. Append entries as they happen; don't reconstruct after the fact.

**For agents working in this repo:** when the human corrects something you proposed or produced, or you catch your own mistake, add an entry under *Corrections* using the template below. Add notably effective prompts under *Prompts*. Don't edit or remove existing entries.

---

## Tools

| Tool | Used for |
|---|---|
| Claude chat (Opus 5.5, medium effort) | Planning and review partner: strategy, interpreting findings, designing verification, drafting instructions for Claude Code, drafting the write-ups |
| Claude Code (Opus 5.5, extra-high effort) | Profiling, pipeline build, bridge search, sensitivity analysis, packaging |
| Claude Code (Sonnet 5.5, medium effort) | Independent code-blind verification build. A different model was used on purpose, to reduce correlated errors. |

**Workflow:**
- Prompts for Claude Code were drafted in the planning chat and edited by the human before use.
- `CLAUDE.md` sets the agent's guardrails: stage gates, no hardcoded rule values, propose-then-confirm for decisions, and log corrections here.

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
- **Tool / stage:** Claude chat (Opus 5.5, medium effort) · planning
- **What the AI got wrong:** Proposed putting the README Finance rules both in `CLAUDE.md` and in a config file.
- **How it was caught:** Human review of the plan. The rules are deterministic logic and belong only in the code/config layer, not in agent instructions.
- **Fix applied:** Single source of truth. Rule values live only in `config/` and are read by the SQL. `CLAUDE.md` holds only agent instructions (stage gates, conventions, guardrails) and pointers to the spec and the config.
- **Why it matters:** Two copies of the same rules drift over time. That is the exact governance failure the exercise is about: rule ownership and a single definition of R&M.

### C-02 · 2026-10-15 · Lenient amount parse would have silently dropped ERP-B amounts
- **Tool / stage:** Claude Code (Opus 5.5, extra-high effort) · profiling
- **What the AI got wrong:** The first ERP-B profiling view parsed AmountCAD with `TRY_CAST(... AS DECIMAL)`. 18 cells are text with thousands separators (`'4,581.93'`, CAD 51,965.23, all on 73xx-RM accounts). Those would have become NULL and fallen out of every sum without an error.
- **How it was caught:** A separate typed read of the sheet failed on cell E291. The column profile then showed 1,486 of 1,504 amounts parsing. Listing every non-plain amount found the 18 text cells.
- **Fix applied:** The profiling lens strips commas before casting and is labelled as a lens. `amount_text_shapes` and `amount_nonplain_rows` list the cells. The subtotal tie-out (`subtotal_check`, 0.00 on all 31) confirms they are real amounts. How the build treats them is left to the human (findings Q-6).
- **Why it matters:** `TRY_CAST` turns a format defect into a silent understatement of R&M. The build needs a row-level check that every amount parsed, not just that the query ran.

### C-03 · 2026-10-15 · JE register total mixed CAD and USD
- **Tool / stage:** Claude Code (Opus 5.5, extra-high effort) · profiling
- **What the AI got wrong:** `totals_by_account` in the JE register profile had an "ALL" row that added the CA entry (JE-0927, CAD 3,302.00) to the six USD entries, giving 27,842.83.
- **How it was caught:** Self-review of the result before writing findings. The CA row's local account and "Fuel – CAD" description show it is not USD.
- **Fix applied:** Totals are now per entity only (US USD 24,540.83; CA CAD 3,302.00), with a comment saying why there is no all-entity total.
- **Why it matters:** A mixed-currency total would carry straight into the bridge as a wrong reconciling amount.

### C-04 · 2026-10-15 · Bridge crashed instead of failing its residual check
- **Tool / stage:** Claude Code (Opus 5.5, extra-high effort) · bridge
- **What the AI got wrong:** `sql/09_bridge.sql` assumed the config table of Accounting's FX overrides always exists. With no override listed, which legitimately means "Accounting used Finance's rate every month", the build stopped with a missing-table error instead of reporting a non-zero residual.
- **How it was caught:** A deliberate failure test: rerunning the build against a scratch config without the September override, expecting check C25 to fail with an 11,681.61 residual.
- **Fix applied:** The bridge SQL now starts from an empty override table when none is configured. The same test then failed cleanly on C25 (residual 11,681.61, only `checks.csv` written), and the real build passes all 27 checks.
- **Why it matters:** A check proves nothing until it has been seen to fail. A crash says "something broke"; a failed C25 says "the bridge doesn't close, by this much".

### C-05 · 2026-10-15 · Verification design mixed bugs with judgment calls
- **Tool / stage:** Claude chat (Opus 5.5, medium effort) · verification design
- **What the AI got wrong:** Proposed a fully blind verification build from the raw files and README only. Any difference would then be ambiguous: an implementation bug, or just a different call on an ambiguity the human had already decided deliberately.
- **How it was caught:** The human challenged what a match or mismatch would actually prove.
- **Fix applied:** Code-blind instead of spec-blind.
  - The verify received the README and `decisions.md`, but no code, config or outputs.
  - It ran on a different model to reduce correlated errors: Sonnet 5.5, medium effort, rather than Opus 5.5, extra-high effort.
  - The Accounting files and the task PDF were withheld, so it couldn't drift toward the expected figure.
- **Why it matters:** Every difference becomes actionable, because it must be a bug in one of the two builds. Result: a 39/39 cell match (V-01). Judgment calls are validated separately through the sensitivity analysis and the bridge (V-05).

### C-06 · 2026-10-15 · Planned stages bundled into one prompt
- **Tool / stage:** Claude chat (Opus 5.5, medium effort) · prompt drafting
- **What the AI got wrong:** Suggested a single Claude Code prompt covering decisions, config and the full build. That was three stages in one turn, against the stage-gated workflow in `CLAUDE.md`.
- **How it was caught:** The human noticed the unusually long agent reasoning and questioned the step size. The `CLAUDE.md` guardrail still held: the agent stopped to confirm decisions before building on them.
- **Fix applied:** The remaining stages ran in Claude Code plan mode. The agent proposes a plan, the human approves or edits it, then the agent executes.
- **Why it matters:** Smaller, gated steps keep judgment with the human and leave a commit per stage.

### C-07 · 2026-10-15 · Branch mapping by prefix heuristic
- **Tool / stage:** Claude Code (Opus 5.5, extra-high effort) · profiling → build
- **What the AI got wrong:** It grouped the 14 raw Whse spellings by their first three letters. That was acceptable as a profiling lens, but not as a production rule: any new spelling would map silently, right or wrong.
- **How it was caught:** Human review of the profiling assumptions before deciding treatments.
- **Fix applied:** An explicit governed map of all 14 raw values to branch codes in `config/rules.toml` (D-04), plus a check that fails on any unmapped value. The failure path was tested in V-03.
- **Why it matters:** For Finance numbers, an unknown value should stop the build, not be guessed.

### C-08 · 2026-10-15 · Wrong prediction: 7335-RM-HYD as a reconciling item
- **Tool / stage:** Claude chat (Opus 5.5, medium effort) · decisions and bridge planning
- **What the AI got wrong:** Predicted that 7335-RM-HYD, which is missing from Accounting's account map, would be a reconciling item of about USD 78k, and wrote that expectation into D-05.
- **How it was caught:** The exhaustive bridge search. The only combination that closes keeps 7335 in Accounting's total. Accounting's close evidently doesn't depend on the map.
- **Fix applied:** The treatment was unchanged, since README rule 6 includes it. The item was reframed in the bridge and data quality log as a zero-impact-this-quarter governance finding: a latent risk that any map-driven automated build would silently drop USD 78k.
- **Why it matters:** The bridge was not forced to match an expectation. The evidence overrode the prior.

### C-09 · 2026-10-15 · Hardcoded values in the scenario engine
- **Tool / stage:** Claude Code (Opus 5.5, extra-high effort) · bridge analysis (self-caught)
- **What the AI got wrong:** `analysis/scenarios.py` hardcoded the quarter-end date and the Elmwood months in its sensitivity scenarios, against the `CLAUDE.md` rule that no rule values are hardcoded.
- **How it was caught:** The agent's own review after its engine reproduced the Part 1 output.
- **Fix applied:** Both values are now read from config.
- **Why it matters:** If the scenario engine kept its own copy of the rules, its results would drift from the pipeline as soon as a rule changed.

### C-10 · 2026-10-15 · Design memo exceeded the one-page limit
- **Tool / stage:** Claude chat (Opus 5.5, medium effort) · Part 4 drafting
- **What the AI got wrong:** The drafted memo ran to about 830 words, against the exercise’s explicit “one page maximum”. The draft was also edited twice for scope (first too timid, then overreaching) before settling on “all ERPs landed and profiled, trusted R&M for two systems”.
- **How it was caught:** Human review of the full repo before submission, reading the package as a reviewer would.
- **Fix applied:** Memo cut to about 490 words: cost table folded into two lines, the “lessons” sub-bullets removed (the data quality log already makes that point), and the 30-day plan compressed to four lines. Substance unchanged.
- **Why it matters:** Rubric constraints are requirements, not style. A thorough memo that breaks the page limit fails the brief it answers.

---

## Prompts

Drafted in the planning chat, edited by the human, run in Claude Code. Trimmed.

**P-01 · Profiling, stage-gated**
> This is the profiling stage only: no transforms, no pipeline, no config. Write profiling queries in DuckDB, one `.sql` file per raw file… Then write `profiling/findings.md`: every anomaly with evidence (row counts, sample rows, amounts). Do not decide treatments; flag anything where the README rule is ambiguous. Stop after that.

*Why it worked:* it kept judgment with the human. Every treatment in `decisions.md` is a confirmed human decision, made from evidence.

**P-02 · Code-blind verification** (fresh session, separate folder, Sonnet 5.5, medium effort)
> This folder contains a README with the Finance rules and `decisions.md` with confirmed decisions… Write a single independent script that produces `rm_q3_by_branch.csv`… Use exact decimal arithmetic for money. If something isn't covered, decide, document it in `verify_notes.md` and continue.

*Why it worked:* the same spec with independent code means any difference is a bug. Withholding the Accounting files meant it couldn't steer toward the expected total.

**P-03 · Bridge with uniqueness**
> Identify the reconciling items that bridge Finance to Accounting to the cent… Explicitly check for alternative combinations that also close, not just the first one that does. For each final item, state who is right, the evidence, and what should change and where.

*Why it worked:* it turned a plausible bridge into a proven unique one.

---

## Verification approach

### V-01 · 2026-10-15 · Blind independent rebuild matches the pipeline to the cent
- **Tool / stage:** Claude Code (Sonnet 5.5, medium effort) as the independent builder; Claude Code (Opus 5.5, extra-high effort) ran the comparison · verify
- **What was checked:** `output/rm_q3_by_branch.csv` from the pipeline (commit `3b72320`).
- **Method:**
  - A separate session on Sonnet 5.5, medium effort, rebuilt Part 1 from the raw data files, the README and `docs/decisions.md` only. It had no access to our code, config, outputs or profiling findings.
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

### V-02 · 2026-10-15 · Agent respected the decision gate
- The agent stopped and asked for confirmation before writing `docs/decisions.md` and building on it, as `CLAUDE.md` requires.
- This held even when the prompt bundled several stages (C-06).

### V-03 · 2026-10-15 · Failure-path test on the branch map
- One Whse map entry was removed in a scratch copy of the config.
- The build exited 1, named the unmapped value (`Elmwood`, 164 rows) and wrote only `checks.csv`, so no stale deliverable was left behind.

### V-04 · 2026-10-15 · Determinism and no hardcoded rules
- A clean rerun reproduces every output byte for byte.
- A search of `sql/` and `run.py` finds no rule values outside comments.
- The pipeline makes no LLM calls.

### V-05 · 2026-10-15 · Judgment calls tested by sensitivity and the bridge
- **Sensitivity.** `docs/sensitivity.md` reruns the build with the most plausible alternative for each decision, D-01 to D-12, and reports which ones are material.
- **Bridge.** The exhaustive search (about 78 million combinations) found exactly one closing combination. In it, Accounting matches Finance's treatment on every decision except September FX and JE-0931. Accounting's own figure therefore independently corroborates the other treatments.
- **Overlaps.** Interactions are scored on real tables, not by adding independent effects. The duplicates-kept and capex-kept effects both differ from their gross profiling amounts by exactly USD 20,511.96, the capex lines inside the duplicated export.

### V-06 · 2026-10-15 · Hand check of the surprising record
- Seeing 7335-RM-HYD inside Accounting's total (C-08), the human confirmed the raw records directly in the workbook: 23 September lines, CAD 108,339.06.
- The workbook's own SUBTOTAL row for that account and month matches the same amount.

### V-07 · 2026-10-15 · Clean clone caught line-ending drift
- The agent's clean-copy test (an extract of the committed tree that was never checked out, compared against the working folder's outputs) reported byte-identical outputs.
- A real git clone on Windows showed every output file as modified: Git converted LF to CRLF on checkout, so regenerated files no longer matched the committed ones. Content was identical (`git diff --ignore-cr-at-eol` empty).
- **Fix:** `.gitattributes` pinning `* text=auto eol=lf`, repo renormalized. A fresh clone now rebuilds with all 27 checks passing and a clean working tree.
- **Why it matters:** only the reviewer's actual path (clone, then run) tests what they will see. A copy that is never checked out cannot catch a commit or checkout problem.

---
