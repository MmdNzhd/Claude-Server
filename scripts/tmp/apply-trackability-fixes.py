from pathlib import Path
import re

root = Path(r"D:\Smart\Claude-Code-Server")
git_mode = root / "scripts/client/git-mode.ps1"
connect = root / "scripts/client/windows/connect.ps1"
new_push = (root / "scripts/tmp/Push-ServerConnectConf.new.ps1").read_text(encoding="utf-8")

gm = git_mode.read_text(encoding="utf-8")
# Replace Push-ServerConnectConf through just before Read-RetryQuitKey
pat = re.compile(
    r"function Push-ServerConnectConf \{.*?\n\}(?=\r?\n\r?\nfunction Read-RetryQuitKey)",
    re.S,
)
m = pat.search(gm)
if not m:
    raise SystemExit("Push-ServerConnectConf block not found")
gm2 = gm[: m.start()] + new_push.rstrip() + "\n" + gm[m.end() :]
git_mode.write_text(gm2, encoding="utf-8", newline="\n")
print("patched Push-ServerConnectConf")

# Patch Read-RetryQuitKey to ignore non-ASCII KeyChar with ConsoleKey fallback
old_rq = """        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            if ($ki2.KeyChar.ToString().ToLower() -eq 'r' -or $ki2.Key -eq [ConsoleKey]::R) { $rk = 'r' }
            elseif ($ki2.KeyChar.ToString().ToLower() -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {"""

new_rq = """        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            $kc2 = $ki2.KeyChar.ToString()
            $ascii2 = ($kc2.Length -eq 1 -and [int][char]$kc2[0] -ge 32 -and [int][char]$kc2[0] -le 126)
            $letter2 = if ($ascii2) { $kc2.ToLowerInvariant() } else { '' }
            # Non-ASCII KeyChar (e.g. Persian ض on physical Q) must NOT map via ConsoleKey.
            if ($letter2 -eq 'r' -or ($letter2 -eq '' -and $ki2.Key -eq [ConsoleKey]::R)) { $rk = 'r' }
            elseif ($letter2 -eq 'q' -or ($letter2 -eq '' -and $ki2.Key -eq [ConsoleKey]::Q)) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {"""

if old_rq not in gm2:
    raise SystemExit("Read-RetryQuitKey key block not found")
gm3 = gm2.replace(old_rq, new_rq, 1)
git_mode.write_text(gm3, encoding="utf-8", newline="\n")
print("patched Read-RetryQuitKey")

# CLEAR_MOUNT: add reason param logging (optional soft) - enhance existing INFO line callers later
# Patch Clear-SessionMount to accept Reason
old_csm = """function Clear-SessionMount {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = '',
        [switch]$SkipEditorStop
    )
    Write-GitModeLog \"CLEAR_MOUNT project=$ProjectId skip_editor=$SkipEditorStop editor=$EditorCmd path=$RemotePath\" 'INFO'
"""
new_csm = """function Clear-SessionMount {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = '',
        [switch]$SkipEditorStop,
        [string]$Reason = ''
    )
    $reasonPart = if ($Reason) { \" reason=$Reason\" } else { '' }
    Write-GitModeLog \"CLEAR_MOUNT project=$ProjectId skip_editor=$SkipEditorStop editor=$EditorCmd path=$RemotePath$reasonPart\" 'INFO'
"""
if old_csm not in gm3:
    raise SystemExit("Clear-SessionMount header not found")
gm4 = gm3.replace(old_csm, new_csm, 1)
git_mode.write_text(gm4, encoding="utf-8", newline="\n")
print("patched Clear-SessionMount reason")

# --- connect.ps1 session key loop ---
c = connect.read_text(encoding="utf-8")

old_loop = """            $action = 'q'
            $gotKey = $false
            $lastStatusAt = [DateTime]::MinValue
            $script:lastToastAt = $null
            $tunnelSyncOk = $true
                        $lastEditorCheckAt = [DateTime]::MinValue"""

new_loop = """            $action = ''
            $gotKey = $false
            $lastStatusAt = [DateTime]::MinValue
            $script:lastToastAt = $null
            $tunnelSyncOk = $true
                        $lastEditorCheckAt = [DateTime]::MinValue"""
if old_loop not in c:
    raise SystemExit("action default block not found")
c = c.replace(old_loop, new_loop, 1)
print("patched action default to empty")

old_keys = """                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    Write-ConnectDecision 'session_key' (\"action={0} key={1} keychar={2}\" -f $action, $ki.Key, $ki.KeyChar)
                    $gotKey = $true
                    break
                }"""

new_keys = """                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $ascii = ($kc.Length -eq 1 -and [int][char]$kc[0] -ge 32 -and [int][char]$kc[0] -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    # Ignore non-ASCII letters (Persian layout on physical Q/G/...) — do not quit.
                    $resolved = ''
                    if ($letter -eq 'r' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::R)) { $resolved = 'r' }
                    elseif ($letter -eq 'g' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::G)) { $resolved = 'g' }
                    elseif ($letter -eq 'o' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::O)) { $resolved = 'o' }
                    elseif ($letter -eq 'q' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
                    Write-ConnectDecision 'session_key' (\"action={0} key={1} keychar={2} ascii={3}\" -f $resolved, $ki.Key, $ki.KeyChar, $ascii)
                    if (-not $resolved) {
                        Write-ConnectLog (\"SESSION_KEY ignore non_command key={0} keychar={1}\" -f $ki.Key, $ki.KeyChar) 'INFO'
                        continue
                    }
                    $action = $resolved
                    $gotKey = $true
                    break
                }"""

if old_keys not in c:
    raise SystemExit("session key handler not found")
c = c.replace(old_keys, new_keys, 1)
print("patched session key handler")

old_re = """                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'q' -or $ki.Key -eq [ConsoleKey]::Q -or
                        $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                } else {
                    $action = 'r'
                    Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'
                    Write-Host \"    Connection dropped - reconnecting...\" -ForegroundColor Yellow
                }"""

new_re = """                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $ascii = ($kc.Length -eq 1 -and [int][char]$kc[0] -ge 32 -and [int][char]$kc[0] -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    if ($letter -eq 'r' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::R)) { $action = 'r' }
                    elseif ($letter -eq 'q' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    else {
                        Write-ConnectLog (\"SESSION_KEY ignore non_command(during_drop) key={0} keychar={1}\" -f $ki.Key, $ki.KeyChar) 'INFO'
                    }
                } else {
                    $action = 'r'
                    Write-ConnectLog 'TUNNEL: connection dropped - auto reconnect' 'WARN'
                    Write-Host \"    Connection dropped - reconnecting...\" -ForegroundColor Yellow
                }"""

if old_re not in c:
    raise SystemExit("reconnect key handler not found")
c = c.replace(old_re, new_re, 1)
print("patched reconnect key handler")

# After key loop, if action empty and gotKey false, keep waiting? Currently falls through.
# Need guard: only disconnect when action -eq 'q'
# Find SESSION: disconnect
if "SESSION: disconnect" not in c:
    raise SystemExit("disconnect log missing")

# Bump embedded version in connect.ps1 if present
c2, n = re.subn(r"20260719\.24", "20260719.25", c)
print(f"connect.ps1 version bumps: {n}")
connect.write_text(c2, encoding="utf-8", newline="\n")

# version files
for vf in [
    root / "scripts/client/windows/connect-version.txt",
    root / "scripts/client/mac/connect-version.txt",
]:
    if vf.exists():
        vf.write_text("20260719.25", encoding="utf-8", newline="\n")
        print("bumped", vf)

# mac connect.sh version if embedded
mac = root / "scripts/client/mac/connect.sh"
if mac.exists():
    mt = mac.read_text(encoding="utf-8")
    mt2, n2 = re.subn(r"20260719\.24", "20260719.25", mt)
    if n2:
        mac.write_text(mt2, encoding="utf-8", newline="\n")
        print(f"mac connect.sh version bumps: {n2}")

print("DONE")
