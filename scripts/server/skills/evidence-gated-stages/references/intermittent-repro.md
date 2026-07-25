# Intermittent / Flaky Repro Protocol

Use when the smoking gun is not 100% reproducible. Do **not** skip to IMPLEMENT.

## Decision tree

```text
Can you reproduce ≥2/3 attempts in a controlled env?
  YES → treat as class A candidate; continue IRON LAW with RED that fails when gun appears
  NO  → is it environment-bound (timing, load, specific machine)?
          YES → write repro protocol (steps, env, seed, wait); capture artifacts (logs, traces)
                → classify: flake (class C) vs latent A
          NO  → gather-only stage: expand VERIFY fingerprint; NO production IMPLEMENT
                → stop and ask user for better signal / access
```

## Stabilize before RED

1. Pin versions (repo SHA, artifact SHA, live build id).
2. Reduce concurrency; disable unrelated noise.
3. Capture **exact** non-secret gun substring + surrounding 5 lines.
4. Prefer automatable probe (script/test) even if pass-rate < 100%.

## Class C vs A

| Signal | Class | Action |
|--------|-------|--------|
| Test fails randomly without product change | C | Quarantine or fix harness; do not block product DONE alone |
| User path fails sometimes with same gun | A | Must fix or accept known risk in plan |
| Only under load / race | A | RED that injects race or load; document |

## Pack fields

- VERIFY: `repro_rate=k/n`, protocol path
- RED_TEST: may be probabilistic; document threshold
- RUNTIME_GATE: for intermittent, prefer metric/window proof over single session

Compose: `systematic-debugging` for investigation discipline; this doc for gate decisions.
