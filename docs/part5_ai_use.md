# Part 5: How I used AI

## Tools and roles

I worked with Anthropic's Claude in basically two tiers:

| Tool | Role |
|---|---|
| Claude chat (Opus 5.5, medium effort) | For planning and review: strategy, interpreting findings, designing the verification, drafting instructions for Claude Code and reviewing its output. |
| Claude Code (Opus 5.5, extra-high effort) | Profiling, pipeline build, bridge search and decision sensitivity analysis. |
| Claude Code (Sonnet 5.5, medium effort) | Independent verification build. A different model was used on purpose to reduce correlated errors. |

I was in the middle of these tiers at all times. I decided every data treatment, edited the instructions and reviewed both tools' output critically. A `CLAUDE.md` was placed in the repo's root to set the agent's guardrails:
- Work stage by stage, and stop after each stage.
- No rule values in code.
- Propose decisions and wait for confirmation.
- Log corrections.

The full running log can be found in `docs/ai_log.md`.

## Most useful instructions

The instructions were drafted in the planning chat and further refined by me before prompting the coding agent.

1. **Profiling, stage-gated:** "This is the profiling stage only: no transforms, no pipeline, no config. Report every anomaly with evidence. Do not decide treatments; flag anything where the README rule is ambiguous. Stop after that." This kept every judgment call within my control. Every treatment in `docs/decisions.md` is a validated human decision.
2. **Code-blind verification:** a fresh session on a different model was given only the raw ERP files, the README and `decisions.md`. It got no code, config, outputs or any of the Accounting files, this way it could not steer toward the expected total. Instruction: "Write a single independent script… use exact decimal arithmetic for money."
3. **Bridge:** "Explicitly check for alternative combinations that also close, not just the first one that does." This established the bridge as the unique solution rather than just a plausible one.

## What the AI got wrong

Ten entries exist in the full log. Some notable examples:

- **A silent data loss (Claude Code).** It parsed Lakeshore amounts with a lenient cast that turned unparseable text into NULL instead of failing. 18 text amounts with thousands separators (CAD 51,965.23) would have become NULL and dropped out of R&M. A strict typed read failed on one cell and exposed it, and the subtotal rows tying out confirmed the fix.
- **Verification design (planning chat).** It first proposed a fully blind rebuild. I asked what a match or mismatch would actually prove: any difference would mix implementation bugs with judgment calls I had already made deliberately. It was redesigned as just code-blind, so that any difference would point to an implementation bug.
- **A wrong prediction (planning chat).** It expected account 7335-RM-HYD, which was missing from Accounting's map, to be a reconciling item. The exhaustive bridge search disproved this: Accounting's total already includes it. The finding was reframed as a latent governance risk.
- **A check that could not fail properly (Claude Code).** A deliberate failure test showed the bridge crashing instead of failing its residual check. It was fixed and retested, since a check can only be relied on once it has been seen to fail.
- **Rules duplicated in agent instructions (planning chat).** It proposed putting the Finance rules in both `CLAUDE.md` and config. Now config is the single source of truth.

## How the output was checked
- 27 build checks:
  - row and amount conservation per source
  - format checks on the output files
  - bridge residual exactly 0.00
  - every bridge item traces to a source record
- Failure test: removing one branch mapping made the build fail and pointed to the exact value.
- Reruns are byte-identical. A search confirmed no rule values are hardcoded.
- **Independent build: all 13 cells match to the cent** (USD 14,090,228.96).
- Bridge uniqueness: exactly one combination closes out the difference, out of about 78 million evaluated.
- Human review of every stage's output.

## How much of the code was AI-written?

**Approximately 95% or more.** 
My code writing skills allow me to read, understand and change the code if I need to, but I could never write it at the speed an LLM can. That's why I focused most of my efforts on:
- the specification and stage design
- every treatment decision
- the verification design
- review

Where the AI was wrong, I corrected it by changing the instruction or the rule, not by hand-editing code (except for documentation, where human tone and wording does impact the result in some cases). The SQL part is deliberately short and readable with one pipeline step per file, as is the main run.py script so that it can be easy to explain and change live if needed.
