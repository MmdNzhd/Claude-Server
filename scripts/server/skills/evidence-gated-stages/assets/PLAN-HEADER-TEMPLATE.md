# <Feature / Incident> — Evidence-Gated Plan

> **Skill:** `evidence-gated-stages` (`author` → `execute` → `closeout`)  
> **Compose:** systematic-debugging · TDD · verification-before-completion · SDD as needed  
> **Release:** LOCKED until explicit deploy/publish quote  
> **Done model:** stages → candidate_complete; Product DONE → closeout scorecard only

**Goal:** <one sentence>

**Identities (rebased now):**
- repo=`<ver/sha>`
- artifact=`<path:ver/sha>`
- live=`<ver/session>`

**Smoking guns (must disappear):**
| ID | Substring / metric | First seen | P0? |
|----|--------------------|------------|-----|
| G1 | `|` | `|` | yes/no |

**Hypothesis ledger:** `docs/<feature>-evidence/HYPOTHESES.md`

**Class B known debt (non-blocking):**
- …

**P0 stages (RUNTIME_GATE required):** `<ids>`

**Forbidden release patterns:**
- `<regex or cmd list>`

**Evidence dir:** `docs/<feature>-evidence/`  
**Scaffold:** `python3 ~/.cursor/skills/evidence-gated-stages/scripts/scaffold-evidence-dir.py --root . --feature <slug>`

---

## Hypotheses (stub)

### H1 — …
- Status: candidate
- Claim:

---

## Stages

### Stage 0 — Baseline
- Exit: guns captured; evidence dir created
- Pack: `STAGE-0.md`

### Stage 1 — Reproduce
- Entry / allowed / forbidden:
- Exit evidence (command):
- Pack: `STAGE-1.md`

### Stage 2 — …
- …

### Stage D — Release (LOCKED)
- Unlock only on new explicit user quote (paste into pack VERIFY)
