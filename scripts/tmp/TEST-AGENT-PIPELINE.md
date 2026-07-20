# HARD TEST Agent A — Connect pipeline

**Date:** 2026-07-20  
**Project:** `-p claude-code-server`  
**Command:**

```text
laptop-exec run -p claude-code-server -- cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Smart\\Claude-Code-Server\\scripts\\client\\tests\\test-connect-pipeline.ps1"
```

Full stdout/stderr: `scripts/tmp/TEST-PIPELINE-OUT.txt`  
(Re-run also stamped `=== EXIT_CODE=1 ===` at end of that file.)

Tunnel: UP (windows, active_mount=claude-code-server). No deploy.

---

## Exit code

| Source | Value |
|--------|-------|
| `test-connect-pipeline.ps1` / laptop-exec | **1** |
| Footer in `TEST-PIPELINE-OUT.txt` | `EXIT_CODE=1` |

**Nonzero ⇒ not a pass.**

---

## Pass / fail counts

| | Count |
|--|------:|
| PASS | 79 |
| FAIL | **1** |
| Total asserts observed | 80 |

Suite message: `1 test(s) failed.`

---

## EVERY failed assert

### 1. `windows\connect.ps1 has no smart/curly quotes (PS 5.1 break)`

- **Assert:** `$src -notmatch '[\u201C\u201D\u2018\u2019]'` after `Get-Content $path -Raw` (default encoding, no `-Encoding UTF8`).
- **Location:** `scripts/client/windows/connect.ps1` **line 1581** (comment only).
- **UTF-8 truth on disk:**
  - `U+2014` EM DASH (`—`) at bytes `E2 80 94`
  - `U+0636` Arabic letter DAD (`ض`) later in the same comment (`(ض on Q)`)
- **Why the assert trips:** PS 5.1 default `Get-Content` (system ANSI) mis-decodes UTF-8 `E2 80 94` as three chars ending in **`U+201D` RIGHT DOUBLE QUOTATION MARK**, so the curly-quote regex matches even though the UTF-8 file has **no** `U+201C/U+201D/U+2018/U+2019`.
- **Cross-check:**
  - `Get-Content -Encoding UTF8` → curly regex **false**
  - `[Parser]::ParseFile` → **0** parse errors (adjacent assert **PASS**: `parses cleanly in PS 5.1`)

Comment text (UTF-8):

```text
# VK fallback ONLY for null/control KeyChar — never for Persian/other printable non-ASCII (ض on Q).
```

---

## Flaky vs real

| Failure | Flaky? | Classification |
|---------|--------|----------------|
| smart/curly quotes assert | **No** — reproducible every run | **Real suite failure** (exit 1). Root cause is encoding-sensitive assert + UTF-8 punctuation/Persian in a comment, **not** a literal curly quote that breaks the parser. Still a **HARD FAIL** of this pipeline: the suite failed as written. |

Not intermittent. Not environment flake. Not “almost pass.”

---

## Related smoke / subsets

`test-connect-pipeline.ps1` is **self-contained** — it does **not** invoke other suites.

`run-all.ps1` lists `connect-pipeline` among many suites; **not run** here (Agent A scope = this pipeline only; no subset spawn from the script itself).

---

## Verdict

# HARD FAIL

- Exit code **1**
- **1** failed assert (documented above)
- **79** passes do not redeem a nonzero exit

**Do not mark pass.** Fix options (out of scope for this agent): replace `—` / `ض` in that comment with ASCII, or teach the test to read `-Encoding UTF8` / scan UTF-8 bytes for real curly quotes only.
