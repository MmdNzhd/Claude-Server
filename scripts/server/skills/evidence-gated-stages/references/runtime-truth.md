# Runtime Truth — repo vs artifact vs live

## Why this exists

Common false DONE: unit/contract tests green in git, while users still launch an old Desktop folder, container tag, or IIS site. Smoking guns remain in day logs.

## Layers

| Layer | Question | Proof examples |
|-------|----------|----------------|
| **Repo** | Is source correct? | git diff, targeted tests |
| **Artifact** | Do launched bits match repo? | SHA12 of files in Desktop/publish/IIS/image |
| **Live** | Is the bad behavior gone? | log substring absent, metric, manual repro script |

## Hard rules

1. Every VERIFY states all three labels (use `n/a` with reason if needed).
2. `artifact_sync=yes` ⇒ **entire sync set** for the stage (not one file of many).
3. Prefer content hash (SHA12) over "I copied it".
4. `runtime_green=yes` ⇒ user-facing path, not only CI sandbox.
5. `pending_reconnect` / stale session version ⇒ not product DONE.
6. Server-installed CLIs/services may lag until release stage — report as installed drift, do not claim live fixed.
7. Never shrink authoritative remote logs/DBs to "match" local (append/merge only).

## Sync set definition

At IMPLEMENT time, write:

```text
sync_set:
  - root: <Desktop/App or publish/out or container>
    files: [a, b, c]   # or "all client scripts"
```

Closeout compares that set.

## Decision table

| repo | artifact | runtime | Claim allowed |
|------|----------|---------|---------------|
| yes | yes | yes | Product stage DONE |
| yes | yes | pending | Repo+artifact only; say pending |
| yes | no | * | Not DONE — sync first |
| yes | yes | still_live | Not DONE — fix incomplete |
| no | * | * | Not DONE |

## Installed (fourth label)

`installed` = what is on the **server/PATH** (e.g. `/usr/local/bin/tool`) independent of the user artifact root.

- May lag repo until release stage — expected under deploy lock.
- Never claim `artifact_sync=yes` because installed matches, or vice versa.
- Closeout may report `INSTALLED_DRIFT` as observation without failing ARTIFACT_SYNC if Desktop/publish sync is OK.
