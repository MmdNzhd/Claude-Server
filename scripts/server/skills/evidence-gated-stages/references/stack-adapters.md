# Stack Adapters

Name **one authoritative command** per stage exit. Do not dump framework tutorials.

## .NET

| Intent | Example authoritative proof |
|--------|----------------------------|
| Unit/regression | `dotnet test --filter FullyQualifiedName~Area.Bug` |
| API | Integration test / WebApplicationFactory |
| Artifact | Publish dir or IIS site file SHA12 vs repo |
| UI | Playwright only if stage requires user path |

Record: TFM, `Debug|Release`, which host launches the site.

## React / frontend

| Intent | Example |
|--------|---------|
| Unit | `pnpm exec vitest run path/to/spec` |
| Build artifact | `pnpm build` + hash of `dist/` |
| User journey | Playwright/Cypress critical path |
| Served bits | CDN/static server object etag/SHA |

## Node / Nest / Express

| Intent | Example |
|--------|---------|
| Unit | `pnpm test -- <file>` / `vitest run` |
| API | supertest against app factory |
| Artifact | built `dist/` or Docker image digest |

## Python

| Intent | Example |
|--------|---------|
| Unit | `pytest -k name` inside **serving** venv/container |
| API | `httpx`/`curl` against running app |
| Package | wheel name+version or image digest |

## Django / FastAPI

Same as Python; pin settings module / ASGI app. Prefer tests that import the
same settings as the process users hit.

## Go

| Intent | Example |
|--------|---------|
| Unit | `go test ./pkg/foo -run Name` |
| Artifact | binary SHA or image digest |

## SQL / migrations

| Intent | Example |
|--------|---------|
| Schema | migration dry-run + idempotent apply on disposable DB |
| Data bug | query fixture asserting gun row absent/present |
| Never | claim live fixed from migration file alone without applied proof |

## Infra / scripts / agents

| Intent | Example |
|--------|---------|
| Contract | Static test on forbidden/required pattern |
| Artifact | Desktop/install directory SHA sync set |
| Live | Day-log gun substring count = 0 |

## Monorepo mapping

When bug spans API + UI + job:

```text
Stage N   : API RED/GREEN
Stage N+1 : UI RED/GREEN
Stage N+2 : E2E adjacent verify
Stage N+3 : artifact sync all roots
```

Do not collapse cross-repo proofs into one vague "tests passed".
