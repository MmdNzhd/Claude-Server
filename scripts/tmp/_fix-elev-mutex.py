from pathlib import Path

# --- connect.ps1 elevation block ---
p = Path("scripts/client/windows/connect.ps1")
t = p.read_text(encoding="utf-8")
old = """if (-not $script:RunAdminFix) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) + $args
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevArgs -PassThru -Wait
            exit $(if ($null -ne $p -and $null -ne $p.ExitCode) { $p.ExitCode } else { 1 })
"""
new = """if (-not $script:RunAdminFix) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        # connect-boot holds Global\\ClaudeConnect in THIS process. An elevated child cannot
        # inherit that Mutex handle; if we keep holding it across RunAs -Wait, the child
        # always hits SINGLE_INSTANCE: blocked and the UI never appears.
        if ($global:ClaudeConnectBootMutex) {
            try { $global:ClaudeConnectBootMutex.ReleaseMutex() } catch { }
            try { $global:ClaudeConnectBootMutex.Dispose() } catch { }
            $global:ClaudeConnectBootMutex = $null
        }
        $env:CLAUDE_CONNECT_BOOT_MUTEX = $null
        # Prefer elevating connect-boot so the admin process re-acquires the mutex atomically.
        $bootPs1 = Join-Path $PSScriptRoot 'connect-boot.ps1'
        $elevTarget = if (Test-Path -LiteralPath $bootPs1) { $bootPs1 } else { $PSCommandPath }
        $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $elevTarget) + $args
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $elevArgs -PassThru -Wait
            exit $(if ($null -ne $p -and $null -ne $p.ExitCode) { $p.ExitCode } else { 1 })
"""
if old not in t:
    raise SystemExit("elevation block not found")
p.write_text(t.replace(old, new, 1), encoding="utf-8", newline="\n")
print("patched connect.ps1")

# --- bump version ---
for rel in [
    "scripts/client/windows/connect-version.txt",
    "scripts/client/mac/connect-version.txt",
]:
    Path(rel).write_text("20260720.26", encoding="utf-8", newline="\n")
win = Path("scripts/client/windows/connect.ps1")
wt = win.read_text(encoding="utf-8")
wt2 = wt.replace("ConnectVersion = '20260720.25'", "ConnectVersion = '20260720.26'", 1)
if wt2 == wt:
    raise SystemExit("ConnectVersion bump failed")
win.write_text(wt2, encoding="utf-8", newline="\n")
mac = Path("scripts/client/mac/connect.sh")
mt = mac.read_text(encoding="utf-8")
mt2 = mt.replace("CONNECT_VERSION='20260720.25'", "CONNECT_VERSION='20260720.26'", 1)
if mt2 == mt:
    raise SystemExit("mac version bump failed")
mac.write_text(mt2, encoding="utf-8", newline="\n")
print("bumped to .26")

# --- hard test assert ---
ht = Path("scripts/client/tests/test-hard-multi-agent-regressions.ps1")
h = ht.read_text(encoding="utf-8")
needle = "Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat must not probe/release mutex (TOCTOU)'"
extra = needle + """
Assert ($win -match 'ClaudeConnectBootMutex\\)\\s*\\{\\s*try\\s*\\{\\s*\\$global:ClaudeConnectBootMutex\\.ReleaseMutex') 'connect.ps1 releases boot mutex before UAC elevate'
Assert ($win -match \"Join-Path \\$PSScriptRoot 'connect-boot\\.ps1'\") 'connect.ps1 elevates connect-boot.ps1 when present'
"""
# simpler asserts without crazy regex
marker = "Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat must not probe/release mutex (TOCTOU)'"
add = """
Assert ($win -match 'ReleaseMutex' -and $win -match 'CLAUDE_CONNECT_BOOT_MUTEX' -and $win -match \"connect-boot\\.ps1\") 'connect.ps1 releases boot mutex and elevates via connect-boot before UAC'
"""
if "releases boot mutex and elevates via connect-boot" not in h:
    if marker not in h:
        raise SystemExit("hard test marker missing")
    h = h.replace(marker, marker + add, 1)
    ht.write_text(h, encoding="utf-8", newline="\n")
    print("patched hard test")
else:
    print("hard test already patched")

# p0 version asserts - update .25 to .26 where pinned
p0 = Path("scripts/client/tests/test-p0-connect-fixes.ps1")
if p0.exists():
    p0t = p0.read_text(encoding="utf-8")
    p0t2 = p0t.replace("20260720.25", "20260720.26")
    p0.write_text(p0t2, encoding="utf-8", newline="\n")
    print("patched p0 pins")
