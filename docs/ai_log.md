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

---

## Prompts

<!-- Add the instructions that worked best, verbatim or lightly trimmed, with one line on why. -->

---

## Verification approach

<!-- How AI output was checked: assertions, blind independent rerun, adversarial review. Fill in as built. -->

---

## AI-written code estimate

<!-- Fill in at the end. -->
