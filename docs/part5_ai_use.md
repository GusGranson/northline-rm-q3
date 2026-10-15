# Part 5: How I used AI

## Tools and roles

I worked in two tiers:

| Tool | Role |
|---|---|
| Claude chat (Opus) | Planning and review partner: strategy, interpreting findings, designing the verification, drafting instructions for Claude Code, and reviewing its output. |
| Claude Code, Opus at high effort | Profiling, the pipeline build, the bridge search and the sensitivity analysis. |
| Claude Code, Sonnet | The independent verification build. A different model was used on purpose, to reduce correlated errors. |

I acted as the link between the two tiers: I decided every data treatment, edited the instructions and reviewed both tools' output critically. A `CLAUDE.md` in the repo set the agent's guardrails:
- Work stage by stage, and stop after each stage.
- No rule values in code.
- Propose decisions and wait for confirmation.
- Log corrections.

The full running log is in `docs/ai_log.md`.

## Most useful instructions

The instructions were drafted in the planning chat and refined by me.

1. **Profiling, stage-gated:** "This is the profiling stage only: no transforms, no pipeline, no config. Report every anomaly with evidence. Do not decide treatments; flag anything where the README rule is ambiguous. Stop after that." This kept every judgment call with me. Every treatment in `docs/decisions.md` is a confirmed human decision.
2. **Code-blind verification:** a fresh session on a different model was given only the raw ERP files, the README and `decisions.md`. It got no code, config or outputs, and no Accounting files, so that it could not steer toward the expected total. Instruction: "Write a single independent script… use exact decimal arithmetic for money."
3. **Bridge:** "Explicitly check for alternative combinations that also close, not just the first one that does." This established the bridge as the unique solution rather than merely a plausible one.

## What the AI got wrong, and how I caught it

Nine entries are in the full log. The most instructive:

- **A silent data loss (Claude Code).** It parsed Lakeshore amounts with a lenient cast. 18 text amounts with thousands separators (CAD 51,965.23) would have become NULL and silently dropped out of R&M. A strict typed read failed on one cell and exposed it, and the subtotal tie-out confirmed the fix.
- **Verification design (planning chat).** It first proposed a fully blind rebuild. I asked what a match or mismatch would actually prove: any difference would mix implementation bugs with judgment calls I had already made deliberately. It was redesigned as code-blind, so that any difference would point to an implementation bug.
- **A wrong prediction (planning chat).** It expected account 7335-RM-HYD, which is missing from Accounting's map, to be a reconciling item. The exhaustive bridge search disproved this: Accounting's total already includes it. The finding was reframed as a latent governance risk.
- **A check that could not fail properly (Claude Code).** A deliberate failure test showed the bridge crashing instead of failing its residual check. It was fixed and retested, since a check can only be relied on once it has been seen to fail.
- **Rules duplicated in agent instructions (planning chat).** It proposed putting the Finance rules in both `CLAUDE.md` and config. Now config is the single source of truth.

## How the output was checked
- 27 build checks:
  - row and amount conservation per source
  - format checks on the output file as written
  - bridge residual exactly 0.00
  - no plug items
- Failure-path test: removing one branch mapping made the build fail loudly and name the value.
- Reruns are byte-identical. A search confirmed no rule values are hardcoded.
- **Independent build: all 13 cells match to the cent** (USD 14,090,228.96).
- Bridge uniqueness: exactly one combination closes out of about 78 million evaluated.
- Line-by-line human review of every stage's output.

## How much of the code was AI-written

**Approximately 95% or more.** My contribution was:
- the specification and stage design
- every treatment decision
- the verification design
- review

Where the AI was wrong, I corrected it by changing the instruction or the rule, not by hand-editing code. The SQL is deliberately short and readable, with one pipeline step per file, so that I can explain and change it live.
