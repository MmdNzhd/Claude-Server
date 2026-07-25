# Authoring Checklist (mode=author)

## Baseline
- [ ] Smoking guns are **exact** substrings (copy-pasteable from logs)
- [ ] First-seen timestamps/sessions noted
- [ ] repo/artifact/live labels rebased to **now** (not stale plan versions)
- [ ] Evidence dir path chosen: `docs/<feature>-evidence/`
- [ ] Scaffolded via `scripts/scaffold-evidence-dir.py` (or equivalent files present)

## Stage design
- [ ] Causal order (fix B does not precede proof A)
- [ ] P0 ids marked for RUNTIME_GATE
- [ ] Each stage has entry / allowed / forbidden / exit command
- [ ] Investigate stages forbid production edits
- [ ] Fix stages require RED before IMPLEMENT
- [ ] Adjacent verify covers other layers if cross-stack
- [ ] Release stage present and LOCKED
- [ ] Class-B debt listed so suites do not confuse

## Hypotheses
- [ ] Ledger stub created ([hypothesis-ledger.md](hypothesis-ledger.md))
- [ ] At least one plausible alt hypothesis to falsify

## Global constraints
- [ ] Forbidden release command patterns listed
- [ ] Freeze/site policies called out if any
- [ ] Env I/O method noted if nonstandard (e.g. SSH-first)

## Deliverable
- [ ] Plan uses header template fields
- [ ] User can approve/execute without guessing paths
- [ ] Stopped for approval unless execute already ordered

- [ ] Note propose≠admit: stages end as candidates; Product DONE = closeout
- [ ] Point plan at [propose-admit](propose-admit.md) / [sources](sources.md) if novel gates

- [ ] Handoff block ready if session may end mid-plan ([session-handoff](session-handoff.md))
