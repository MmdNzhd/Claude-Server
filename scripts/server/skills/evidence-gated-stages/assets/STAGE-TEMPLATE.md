> **Skeleton only** — `validate-pack.py` will return INVALID until RUNTIME_GATE/VERIFY are filled. See [EXAMPLE-PACK-FILLED.md](EXAMPLE-PACK-FILLED.md).

# STAGE-<id> Evidence Pack

## ID
- Stage: `<id>`
- Baseline/version: `<label>`
- Timestamp: `YYYY-MM-DDTHH:MMZ`
- `deploy_ran=no`

## VERIFY
- Live fingerprint: `<session/time/substring>`
- Code anchor: `<path:symbol>`
- `still_live=yes|no` proof: `...`
- Identity: `repo=<...> artifact=<...> live=<...>`

## RESEARCH
1. https://example.com/a — <why>
2. https://example.com/b — <why>
- Changes: <bullets>
- Will NOT do: <bullet>

## RED_TEST
```
<command>
<failing output excerpt>
```
<!-- Baseline may use: N/A reason=... -->

## IMPLEMENT
- Files: `<paths>`
- Intent: `<one sentence>`
- `drive_by=none`
- sync_set: `<roots/files or n/a>`

## GREEN_TEST
```
<command>
<pass summary>
```

## RUNTIME_GATE
- `signature_absent=yes|pending_reconnect|N/A`
- reason/proof: `...`

## ARTIFACT_SYNC
- `artifact_sync=yes|n/a`
- proof: `SHA12 ...` or reason
- sync_set checked: `<list>`

## GATE
`STAGE_<id>_DONE YYYY-MM-DDTHH:MMZ deploy_ran=no N+1 unlocked`
