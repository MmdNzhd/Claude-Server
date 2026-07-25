# Hypothesis Ledger

Keep in the plan or `docs/<feature>-evidence/HYPOTHESES.md`.
Template: [assets/HYPOTHESES-TEMPLATE.md](../assets/HYPOTHESES-TEMPLATE.md)

## Format

```markdown
## H1 — <short name>
- Status: candidate | accepted | rejected
- Claim: …
- Predictions: …
- Evidence for: …
- Evidence against: …
- Code locus (required if accepted): path:symbol
- Stage that resolved: …
```

## Rules

1. Prefer **one active candidate** while probing (systematic-debugging).
2. Rejected hypotheses stay listed so later agents do not retry them.
3. Accepted hypothesis must name code locus (`path:symbol`).
4. No IMPLEMENT on production code until one hypothesis is `accepted`
   (except pure reproduce instrumentation).
5. If closeout finds guns still live after accepted H → reopen ledger (R6).
6. "Multiple accepted" only when independent subsystems; say so explicitly.
