# STAGE-4 Evidence Pack (example filled — synthetic)

## ID
- Stage: `4`
- Baseline/version: `app 1.2.3-dev`
- Timestamp: `2026-07-22T20:00Z`
- `deploy_ran=no`

## VERIFY
- Live fingerprint: `session=deadbeef01 @ 19:55 Z gun="NullReferenceException at OrderService.Checkout"`
- Code anchor: `src/Orders/OrderService.cs:Checkout`
- `still_live=yes` proof: 2 hits in app log last hour
- Identity: `repo=1.2.3-dev artifact=Desktop/App@old live=1.2.2`

## RESEARCH
1. https://learn.microsoft.com/en-us/dotnet/api/system.nullreferenceexception — NRE means null deref
2. docs/orders-pricing.md — price can be null for draft SKUs
- Changes: null-guard + regression test for draft SKU checkout
- Will NOT do: broad try/catch swallowing

## RED_TEST
```
dotnet test --filter Checkout_DraftSku_Throws
Failed Checkout_DraftSku_Throws — expected no NRE
```

## IMPLEMENT
- Files: `src/Orders/OrderService.cs`, `tests/Orders/CheckoutTests.cs`
- Intent: treat null price as validation error, not NRE
- `drive_by=none`
- sync_set: `publish/out` files `[OrderService.dll, app.runtimeconfig.json]`

## GREEN_TEST
```
dotnet test --filter Checkout_DraftSku
Passed: 2 Failed: 0
```

## RUNTIME_GATE
- `signature_absent=yes`
- proof: `rg "NullReferenceException at OrderService.Checkout" logs/app-20260722.log` → 0 matches after redeploy-to-local host

## ARTIFACT_SYNC
- `artifact_sync=yes`
- proof: `SHA12 OrderService.dll repo=A1B2C3D4E5F6 artifact=A1B2C3D4E5F6`
- sync_set checked: `publish/out/OrderService.dll`, `publish/out/app.runtimeconfig.json`

## GATE
`STAGE_4_DONE 2026-07-22T20:15Z deploy_ran=no N+1 unlocked`
