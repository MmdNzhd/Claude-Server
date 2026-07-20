# HARD-GAP Verification: Mutex Leftovers + Update Swap Bug

**Date:** 2026-07-20  
**Project:** claude-code-server (`-p claude-code-server`)  
**Method:** laptop-exec rg/read only (no /mounts/ I/O)

---

## Hunt 1 — Single-instance leftovers (multi-instance must be allowed)

### Verdict: **PASS**

Multi-instance is allowed. No active global mutex, connect.lock flock, or Enter-ConnectSingleInstance path returns false today.

### Evidence

| Pattern searched | Result |
|---|---|
| `Global\\ClaudeConnect` / `New-Object.*Mutex` / `CreateMutex` | **Not found** (only `%LOCALAPPDATA%\ClaudeConnect\` launch-spec dir in `editor-launch.ps1`) |
| `connect.lock` | **Not found** |
| `connect.lock` flock | **Not found** |
| `already running` (connect scripts) | **Not found** (only unrelated server/designer strings) |

**Active implementations (always allow):**

- `scripts/client/connect-ui.ps1:109-116` — `Enter-ConnectSingleInstance` sets `$script:ConnectInstanceMutex = $null`, logs `MULTI_INSTANCE: allowed pid=… (no global mutex)`, **`return $true`**
- `scripts/client/connect-ui.sh:455-459` — `enter_connect_single_instance()` sets `CONNECT_LOCK_HELD=0`, logs `MULTI_INSTANCE: allowed pid=… (no flock)`, **`return 0`**

**Call sites (dead gate — never blocks):**

- `scripts/client/windows/connect.ps1:197-201` — `if (-not (Enter-ConnectSingleInstance)) { … exit 2 }` but function always returns `$true`
- `scripts/client/mac/connect.sh:226-228` — `if ! enter_connect_single_instance; then exit 2` but function always returns `0`

**Designer / connect-design (explicit multi-instance):**

- `scripts/client/users/designer/connect.ps1:149-151` — comment + `$null = Enter-ConnectSingleInstance` (no exit on false)
- `scripts/client/users/designer/connect.sh:210` — comment: no global flock
- `scripts/client/windows/connect-design.ps1:122-134` — comment + `$null = Enter-ConnectSingleInstance`

**Tunnel isolation (not a single-instance block):**

- `Acquire-TunnelPort` (`git-mode.ps1:433-478`) scans slots 0–9; `connect.ps1:521-524` falls back to base port if none found — does **not** exit

### Non-blocking leftovers (cosmetic / dead code)

| Location | Notes |
|---|---|
| `connect.ps1:199` | `Wait-ConnectExit -Reason 'single_instance'` — unreachable |
| `mac/connect.sh:227-228` | `exit 2` on false — unreachable |
| `users/designer/connect.ps1:645-648,687-690` | `elseif ($script:ConnectInstanceMutex) { ReleaseMutex… }` — defensive cleanup; mutex never created |
| `connect-ui.ps1:112,121` | `$script:ConnectInstanceMutex = $null` variable name retained |
| `connect-ui.sh:457,464` | `CONNECT_LOCK_HELD=0` retained |
| `connect-ui.ps1:226` / `connect-ui.sh:335` | `.sync-lock` on **log upload** only — not connect UI mutex |

**Conclusion:** No mechanism currently prevents a second connect/designer instance. Remaining artifacts are dead paths or harmless legacy names.

---

## Hunt 2 — Update swap bug (`Destination path cannot be a subdirectory of the source: …\.client-update-bak\windows`)

### Verdict: **FAIL** (flat Desktop layout) / **PASS** (published `windows/` subfolder layout + nested-leak cleanup)

The staged swap fix guards the **published** layout (`…/windows/connect.bat` → `packageRoot` = parent). It remains **vulnerable** on the **sync-desktop flat layout** where live `windowsDir`/`WIN_DIR` equals `packageRoot`/`ROOT_DIR`.

### Root cause (still present)

When live windows tree **is** the package root, backup path `.client-update-bak` is **inside** the directory being moved:

```
Move-Item  $packageRoot  →  $packageRoot\.client-update-bak\windows
# ERROR: Destination path cannot be a subdirectory of the source
```

### Windows — `scripts/client/windows/connect-update.ps1`

**Layout resolution (384-397):**

```powershell
$packageRoot = $ScriptDir
$windowsDir = $ScriptDir
if ($leaf -eq 'windows') {
    $packageRoot = Split-Path -Parent $ScriptDir   # GUARD: bak sibling to windows/
    $windowsDir = $ScriptDir
} elseif (Test-Path (Join-Path $ScriptDir 'windows')) {
    $windowsDir = Join-Path $ScriptDir 'windows'
    $packageRoot = $ScriptDir
}
$BakRoot = Join-Path $packageRoot '.client-update-bak'
```

| Layout | ScriptDir | windowsDir | BakRoot | Swap safe? |
|---|---|---|---|---|
| Published ZIP | `…/claude-code/windows` | `…/windows` | `…/claude-code/.client-update-bak` | **PASS** |
| Flat Desktop (`sync-desktop.ps1`) | `…/Claude-Connect` | `…/Claude-Connect` (no `windows/` subdir) | `…/Claude-Connect/.client-update-bak` | **FAIL** |
| Flat + empty `windows/` subdir | `…/Claude-Connect` | `…/Claude-Connect/windows` | inside package root but swap targets subdir only | **PASS** (flat root files not swapped) |

**Nested leak guard (462-465) — PASS for wrong `mac/`/`server/` under staged `windows/`:**

```powershell
foreach ($leakName in @('mac', 'server')) {
    $leak = Join-Path (Join-Path $NewRoot 'windows') $leakName
    if (Test-Path -LiteralPath $leak) { Remove-Item … }
}
```

**Swap (490-512):** `Swap-LiveDir -Live $windowsDir -NewDir $winNew -Bak $winBak` — fails closed with rollback log on error; no pre-check that `$Bak` is not under `$Live`.

**Flat layout deployment path:** `scripts/client/sync-desktop.ps1:34-52` copies `windows\*.ps1` to Desktop root (no `windows/` folder) — triggers FAIL case.

### Mac — `scripts/client/mac/connect-update.sh`

**Layout (69-80, 313-314):**

```bash
# mac/connect-update.sh in mac/ → ROOT_DIR = parent
WIN_DIR="$ROOT_DIR/windows"
[ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"   # flat fallback = entire package root
BAK_ROOT="$ROOT_DIR/.client-update-bak"
```

**Swap (371):** `_swap_dir "$WIN_DIR" "$NEW_ROOT/windows" "$BAK_ROOT/windows"` — same subdirectory bug when `WIN_DIR="$ROOT_DIR"`.

**Missing vs Windows:** no leak scrub of `mac/`/`server/` inside `$NEW_ROOT/windows/` before swap.

### Tests

No test covers flat-layout swap or the subdirectory guard. Existing tests (`test-connect-update-e2e.ps1`, `test-connect-update-quick.ps1`) copy a single `connect.ps1` into a temp dir — minimal layout, not representative of Desktop sync.

---

## Summary

| Hunt | Verdict | One-line reason |
|---|---|---|
| 1 — Single-instance leftovers | **PASS** | Enter functions always allow; no Global mutex / connect.lock; tunnel slots ≠ UI lock |
| 2 — Update swap bug | **FAIL** | Flat Desktop layout (`windowsDir == packageRoot`) still moves root into `.client-update-bak` inside itself; published `windows/` layout + leak scrub PASS |

---

## Recommended fix (Hunt 2 only)

1. Detect flat layout: `windowsDir -eq packageRoot` (or `[ "$WIN_DIR" = "$ROOT_DIR" ]`).
2. Either refuse update with clear message (“re-run sync-desktop / use published windows/ layout”), **or** swap individual tracked files in-place without `Move-Item` on the whole root.
3. Add regression test: temp dir mimicking `sync-desktop.ps1` flat layout + staged update apply.
4. Mac: mirror Windows leak scrub before swap; same flat-layout guard.
