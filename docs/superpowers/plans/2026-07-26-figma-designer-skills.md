---
name: Figma designer skill
overview: "Heavy-task-plan Stage 2/3: TDD-first fleet deploy of official Figma skills (figma-use + figma-generate-design + figma-create-new-file) plus Smart figma-designer router and cheat sheet. No code until user confirms."
todos:
  - id: t1-red-tests
    content: "Task 1 RED: write test-figma-skills-pack.ps1 + verify.sh assertions (must FAIL before skills exist)"
    status: completed
  - id: t2-vendor
    content: "Task 2: vendor official skill trees from figma/mcp-server-guide + VENDOR.md pin"
    status: completed
  - id: t3-green-repo
    content: "Task 3 GREEN: repo pack tests pass; fix any missing required files"
    status: completed
  - id: t4-router-rule-docs
    content: "Task 4: figma-designer SKILL.md + figma-design.mdc + cursor-mcp-pack.md prompts"
    status: completed
  - id: t5-deploy-wire
    content: "Task 5 RED then GREEN: install.sh + add-user.sh deploy wiring; extend pack test for shell content"
    status: completed
  - id: t6-live-smoke
    content: "Task 6: deploy on server + verify on taraneh home + Reload Window smoke (manual gate)"
    status: in_progress
isProject: false
---

# Figma Designer Skills Pack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Heavy-task-plan:** Stage 1 discovery done; this is Stage 2. **Stage 3 = user go-ahead required before any implementation.** Stage 4 uses `parallel-phased-execution` (TDD RED→GREEN waves). On execute, also copy this plan to `docs/superpowers/plans/2026-07-26-figma-designer-skills.md`.

**Goal:** Fleet-install official Figma write-to-canvas skills plus a thin Smart router so Cursor users (e.g. Taraneh) can say “build this page from requirements” / “edit this selection” without knowing the new Figma skill structure.

**Architecture:** Vendor `figma-use` (+ full `references/`), `figma-generate-design`, and `figma-create-new-file` from [figma/mcp-server-guide](https://github.com/figma/mcp-server-guide) into `scripts/server/skills/`. Add Smart `figma-designer` router + expand `figma-design.mdc` + docs cheat sheet. Deploy via the same `install.sh` / `add-user.sh` tree-copy pattern used for plan-flow skills. **MCP auth path unchanged** (`mcp-via-xray` + golden `figu_` token).

**Tech Stack:** Cursor skills (`~/.cursor/skills/`), Figma remote MCP, bash deploy (`install.sh` / `add-user.sh` / `verify.sh`), PowerShell repo regression test (`scripts/client/tests/`), optional live SSH smoke.

## Global Constraints

- English only in repo (comments, skills, docs, tests, error strings).
- Do not commit Figma OAuth tokens / secrets.
- Skip Linux user `designer` for Cursor skill/MCP sync (unchanged).
- Official skill trees: vendor as-is; do not rewrite Figma `SKILL.md` bodies.
- v1 skills only: `figma-use`, `figma-generate-design`, `figma-create-new-file`, `figma-designer` (no slides/figjam/motion/swiftui/community pack).
- TDD: failing pack tests land before vendored trees and before deploy wiring claims green.
- Commits only if user asks.

## File map

| Path | Responsibility |
|---|---|
| `scripts/client/tests/test-figma-skills-pack.ps1` | Repo assertions: required skill files + install/add-user/verify wiring strings |
| `scripts/server/skills/figma-use/**` | Official write-to-canvas foundation + references |
| `scripts/server/skills/figma-generate-design/**` | Official multi-section screen builder |
| `scripts/server/skills/figma-create-new-file/**` | Official new file helper |
| `scripts/server/skills/figma-designer/SKILL.md` | Smart router + prompt templates |
| `scripts/server/skills/FIGMA-SKILLS-VENDOR.md` | Source URL + commit SHA + refresh notes |
| `scripts/server/cursor-rules/figma-design.mdc` | In-Figma vs design-to-code routing |
| `docs/cursor-mcp-pack.md` | Designer quick prompts |
| `scripts/server/commands/install.sh` | Golden + per-user tree deploy |
| `scripts/server/commands/add-user.sh` | New-user tree deploy (fix current gap) |
| `scripts/server/commands/verify.sh` | Soft checks for skill presence |

## Discovery summary (Stage 1 — done)

- Pure thin Smart skill cannot replace `figma-use` (~456KB Plugin API typings + gotchas); official docs mark it mandatory before `use_figma`.
- Fleet has MCP + thin rule; **zero** official Figma Cursor skills installed.
- Claude `figma@claude-plugins-official` ≠ Cursor skills.
- `add-user.sh` currently skips context7/figma-design install loop (only full `install.sh` pushes them).

## Approach (locked)

**C router + core B vendor** (not pure C). Trade-off accepted: larger repo skill trees vs broken write-to-canvas without references.

## Wave / write-set notes (for Stage 4)

| Wave | Slices | Write-set | Gate |
|---|---|---|---|
| W0 | RED pack test only | `test-figma-skills-pack.ps1` | Test fails as expected |
| W1 | Vendor 3 official trees + VENDOR.md | `skills/figma-*` official dirs | Pack file-existence asserts pass |
| W2 | Router + rule + docs (parallel OK) | `figma-designer/`, `figma-design.mdc`, `cursor-mcp-pack.md` | Router content asserts pass |
| W3 | Deploy wiring | `install.sh`, `add-user.sh`, `verify.sh` | Wiring string asserts pass; full pack test green |
| W4 | Live smoke (sequential, server) | user homes via install | `verify` + home path checks |

Hotspot single-writer: `install.sh` (serialize W3).

---

### Task 1: RED — pack regression test

**Files:**
- Create: `scripts/client/tests/test-figma-skills-pack.ps1`
- Modify later (Task 5): `scripts/server/commands/verify.sh` (add asserts that the test will require)
- Optional later: mention in `scripts/client/tests/run-all.ps1` if other server-content tests are listed there

**Interfaces:**
- Consumes: `Get-ServerFile` from `_paths.ps1`
- Produces: failing exit until Tasks 2–5 complete

- [ ] **Step 1: Write the failing test**

```powershell
# scripts/client/tests/test-figma-skills-pack.ps1
# Figma skills pack: required trees, router, deploy wiring (repo-side).
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"
$fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS  $Msg" }
    else { Write-Host "FAIL  $Msg"; $script:fail++ }
}

$required = @(
    'server\skills\figma-use\SKILL.md',
    'server\skills\figma-use\references\gotchas.md',
    'server\skills\figma-use\references\plugin-api-standalone.d.ts',
    'server\skills\figma-generate-design\SKILL.md',
    'server\skills\figma-create-new-file\SKILL.md',
    'server\skills\figma-designer\SKILL.md',
    'server\skills\FIGMA-SKILLS-VENDOR.md'
)
foreach ($rel in $required) {
    $p = Get-ServerFile $rel
    Assert (Test-Path -LiteralPath $p) "exists $rel"
}

$dts = Get-ServerFile 'server\skills\figma-use\references\plugin-api-standalone.d.ts'
if (Test-Path -LiteralPath $dts) {
    Assert ((Get-Item -LiteralPath $dts).Length -gt 100000) 'plugin-api-standalone.d.ts > 100KB'
}

$router = Get-ServerFile 'server\skills\figma-designer\SKILL.md'
if (Test-Path -LiteralPath $router) {
    $r = Get-Content -LiteralPath $router -Raw
    Assert ($r -match '(?m)^name:\s*figma-designer\s*$') 'figma-designer frontmatter name'
    Assert ($r -match 'figma-use') 'figma-designer requires figma-use'
    Assert ($r -match 'figma-generate-design') 'figma-designer mentions figma-generate-design'
    Assert ($r -match 'Using this Figma file:') 'figma-designer has pasteable prompt template'
}

$rule = Get-ServerFile 'server\cursor-rules\figma-design.mdc'
$ruleRaw = Get-Content -LiteralPath $rule -Raw
Assert ($ruleRaw -match 'figma-designer') 'figma-design.mdc points to figma-designer'
Assert ($ruleRaw -match 'write to canvas|in-Figma|inside Figma|use_figma') 'figma-design.mdc covers write-to-canvas'

$docs = Join-Path $script:RepoRoot 'docs\cursor-mcp-pack.md'
$docsRaw = Get-Content -LiteralPath $docs -Raw
Assert ($docsRaw -match 'Designer quick prompts|figma-designer') 'cursor-mcp-pack.md designer prompts'

$install = Get-Content (Get-ServerFile 'server\commands\install.sh') -Raw
Assert ($install -match 'figma-use') 'install.sh deploys figma-use'
Assert ($install -match 'figma-generate-design') 'install.sh deploys figma-generate-design'
Assert ($install -match 'figma-create-new-file') 'install.sh deploys figma-create-new-file'
Assert ($install -match 'figma-designer') 'install.sh deploys figma-designer'

$addUser = Get-Content (Get-ServerFile 'server\commands\add-user.sh') -Raw
Assert ($addUser -match 'figma-use') 'add-user.sh deploys figma-use'
Assert ($addUser -match 'figma-designer') 'add-user.sh deploys figma-designer'

$verify = Get-Content (Get-ServerFile 'server\commands\verify.sh') -Raw
Assert ($verify -match 'figma-use/SKILL\.md') 'verify.sh checks figma-use skill'

if ($fail -gt 0) { Write-Host "`n$fail FAIL(s)"; exit 1 }
Write-Host "`nALL PASS"
exit 0
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
powershell -NoProfile -File scripts\client\tests\test-figma-skills-pack.ps1
```

Expected: multiple `FAIL  exists server\skills\figma-use\...` and wiring FAILs; exit 1.

- [ ] **Step 3: Do not implement production code in this task** — RED only.

---

### Task 2: Vendor official skill trees

**Files:**
- Create: `scripts/server/skills/figma-use/**` (full tree)
- Create: `scripts/server/skills/figma-generate-design/**`
- Create: `scripts/server/skills/figma-create-new-file/**`
- Create: `scripts/server/skills/FIGMA-SKILLS-VENDOR.md`

**Interfaces:**
- Consumes: upstream `https://github.com/figma/mcp-server-guide` at a pinned commit
- Produces: trees readable by Cursor from `~/.cursor/skills/<name>/` after deploy

- [ ] **Step 1: Clone/sparse-checkout or curl the three skill directories from a pinned commit**

Record SHA in `FIGMA-SKILLS-VENDOR.md`:

```markdown
# Figma skills vendor pin

- Source: https://github.com/figma/mcp-server-guide
- Commit: <full-sha>
- Date: 2026-07-26
- Paths vendored:
  - skills/figma-use/
  - skills/figma-generate-design/
  - skills/figma-create-new-file/
- Refresh: re-copy those trees from a newer commit; re-run test-figma-skills-pack.ps1
- License/terms: Figma Developer Terms (see upstream README)
```

- [ ] **Step 2: Confirm required files on disk** (gotchas.md, plugin-api-standalone.d.ts > 100KB, each SKILL.md).

- [ ] **Step 3: Re-run pack test** — file-existence asserts for official trees should PASS; router/rule/docs/wiring still FAIL (expected).

---

### Task 3: GREEN — repo pack files for router/rule/docs (content)

Deferred content is Task 4; this task only confirms vendor gate:

- [ ] **Step 1: Run**

```powershell
powershell -NoProfile -File scripts\client\tests\test-figma-skills-pack.ps1
```

Expected after Task 2 only: official-tree PASS lines; `figma-designer` / rule / docs / install wiring still FAIL.

---

### Task 4: Smart router + rule + docs

**Files:**
- Create: `scripts/server/skills/figma-designer/SKILL.md`
- Modify: `scripts/server/cursor-rules/figma-design.mdc`
- Modify: `docs/cursor-mcp-pack.md` (Figma section)

**Write-sets:** three files, parallel-safe.

- [ ] **Step 1: Write `figma-designer/SKILL.md`** (English), including:

```yaml
---
name: figma-designer
description: >-
  When the user pastes a figma.com URL or asks to build/edit UI inside Figma
  (page from requirements, edit selection, empty state, settings screen) —
  load this skill first, then official figma-use / figma-generate-design.
---
```

Body must require: file/selection URL; load `figma-use` before every `use_figma`; load `figma-generate-design` for multi-section pages; incremental sections + screenshots; stop if Figma MCP missing; include templates containing the exact substring `Using this Figma file:`.

- [ ] **Step 2: Expand `figma-design.mdc`** — Branch A in-Figma → `figma-designer`; Branch B design→code (existing); mention `/add-plugin figma` as optional only.

- [ ] **Step 3: Docs** — under Figma in `cursor-mcp-pack.md`, add **Designer quick prompts** listing fleet skills and 3 copy-paste prompts (build page, edit selection, new file).

- [ ] **Step 4: Re-run pack test** — router/rule/docs asserts PASS; install/add-user/verify wiring still FAIL until Task 5.

---

### Task 5: Deploy wiring (RED already encoded → GREEN)

**Files:**
- Modify: `scripts/server/commands/install.sh` (golden + per-user loop ~352–405)
- Modify: `scripts/server/commands/add-user.sh` (new-user skill install near laptop-exec / plan skills)
- Modify: `scripts/server/commands/verify.sh` (check `~/.cursor/skills/figma-use/SKILL.md` for UID≥1000 sample users, skip designer)

**Pattern (install.sh):** extend the plan-skill style `cp -a` loop to include:

```bash
for _figma_skill in figma-use figma-generate-design figma-create-new-file figma-designer; do
    if [ -f "$SERVER_DIR/skills/$_figma_skill/SKILL.md" ]; then
        mkdir -p "/usr/local/lib/claude-server/skills/$_figma_skill"
        rm -rf "/usr/local/lib/claude-server/skills/$_figma_skill"
        cp -a "$SERVER_DIR/skills/$_figma_skill" "/usr/local/lib/claude-server/skills/$_figma_skill"
        find "/usr/local/lib/claude-server/skills/$_figma_skill" -type f -exec chmod 644 {} +
        find "/usr/local/lib/claude-server/skills/$_figma_skill" -type d -exec chmod 755 {} +
        ok "$_figma_skill skill -> /usr/local/lib/claude-server/skills/"
    fi
done
```

And inside the per-user loop (skip `designer`), same `cp -a` into `/home/$u/.cursor/skills/$_figma_skill`.

**add-user.sh:** same four trees into `/home/$USERNAME/.cursor/skills/` after existing skill installs.

**verify.sh:** for each non-designer UID≥1000 home, warn/ok if `~/.cursor/skills/figma-use/SKILL.md` missing/present; string must match test regex `figma-use/SKILL\.md`.

- [ ] **Step 1: Implement wiring**
- [ ] **Step 2: Run pack test — expect ALL PASS**

```powershell
powershell -NoProfile -File scripts\client\tests\test-figma-skills-pack.ps1
```

Expected: `ALL PASS`, exit 0.

---

### Task 6: Live smoke (server — after user confirms deploy)

**Files:** none in git (runtime).

- [ ] **Step 1:** From Smart laptop: `sudo-from-laptop --smart -- claude-server install` (or project-equivalent deploy).
- [ ] **Step 2:** On server as root/smart:

```bash
test -f /home/taraneh/.cursor/skills/figma-use/references/gotchas.md && echo OK_use
test -f /home/taraneh/.cursor/skills/figma-generate-design/SKILL.md && echo OK_gen
test -f /home/taraneh/.cursor/skills/figma-designer/SKILL.md && echo OK_router
sudo claude-server verify 2>&1 | grep -i figma
```

- [ ] **Step 3:** Taraneh Cursor: **Reload Window**; confirm Skills list includes `figma-use` / `figma-designer`; one smoke prompt with a real file URL (build one small section). Record pass/fail in wrap-up.

**Gate:** repo pack test green is required before live deploy. Live smoke failure (seat/MCP) is Class B if skills are present but Figma API denies — document seat/permission separately.

## Risks

| Risk | Mitigation |
|---|---|
| Large vendored `plugin-api-standalone.d.ts` in git | Required for correct writes; pin SHA; do not minify |
| Upstream skill churn | `FIGMA-SKILLS-VENDOR.md` refresh procedure |
| Agents Window reads laptop mcp.json | Already documented; skills on server home still help Remote SSH Editor |
| Golden Figma seat View-only | verify seat; writes need Full + edit ACL |
| Pure C temptation | Rejected — router alone is not enough |

## Stage 3 — Confirm (waiting)

Short summary for user go-ahead is in the chat. **No code until explicit approval** (e.g. “go”, “execute”, “پیاده کن”).
