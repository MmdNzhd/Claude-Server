from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
connect = root / 'scripts/client/windows/connect.ps1'
gitmode = root / 'scripts/client/git-mode.ps1'

c = connect.read_text(encoding='utf-8')

# --- Session key handler (healthy tunnel) ---
old1 = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $ascii = ($kc.Length -eq 1 -and [int][char]$kc[0] -ge 32 -and [int][char]$kc[0] -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    # Ignore non-ASCII letters (Persian layout on physical Q/G/...) - do not quit.
                    $resolved = ''
                    if ($letter -eq 'r' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::R)) { $resolved = 'r' }
                    elseif ($letter -eq 'g' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::G)) { $resolved = 'g' }
                    elseif ($letter -eq 'o' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::O)) { $resolved = 'o' }
                    elseif ($letter -eq 'q' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2} ascii={3}" -f $resolved, $ki.Key, $ki.KeyChar, $ascii)
                    if (-not $resolved) {
                        Write-ConnectLog ("SESSION_KEY ignore non_command key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                        continue
                    }
                    $action = $resolved
                    $gotKey = $true
                    break
                }'''

new1 = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                    $ascii = ($code -ge 32 -and $code -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    # VK fallback ONLY for null/control KeyChar — never for Persian/other printable non-ASCII (ض on Q).
                    $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                    $resolved = ''
                    if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $resolved = 'r' }
                    elseif ($letter -eq 'g' -or ($useVk -and $ki.Key -eq [ConsoleKey]::G)) { $resolved = 'g' }
                    elseif ($letter -eq 'o' -or ($useVk -and $ki.Key -eq [ConsoleKey]::O)) { $resolved = 'o' }
                    elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2} ascii={3} useVk={4}" -f $resolved, $ki.Key, $ki.KeyChar, $ascii, $useVk)
                    if (-not $resolved) {
                        Write-ConnectLog ("SESSION_KEY ignore non_command key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                        continue
                    }
                    $action = $resolved
                    $gotKey = $true
                    break
                }'''

# tolerate dash vs en-dash in comment
if old1 not in c:
    # try with en-dash variant from previous patch
    old1b = old1.replace(' - do not quit.', ' — do not quit.')
    if old1b in c:
        old1 = old1b
    else:
        # show nearby for debug
        idx = c.find('SESSION_KEY ignore non_command')
        print('NEAR', repr(c[idx-500:idx+200]) if idx>=0 else 'not found')
        raise SystemExit('session key block not found')

c = c.replace(old1, new1, 1)
print('patched session key useVk')

old2 = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $ascii = ($kc.Length -eq 1 -and [int][char]$kc[0] -ge 32 -and [int][char]$kc[0] -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    if ($letter -eq 'r' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::R)) { $action = 'r' }
                    elseif ($letter -eq 'q' -or ($letter -eq '' -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    else {
                        Write-ConnectLog ("SESSION_KEY ignore non_command(during_drop) key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                    }
                } else {'''

new2 = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                    $ascii = ($code -ge 32 -and $code -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                    if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $action = 'r' }
                    elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    else {
                        Write-ConnectLog ("SESSION_KEY ignore non_command(during_drop) key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                    }
                } else {'''

if old2 not in c:
    raise SystemExit('during_drop block not found')
c = c.replace(old2, new2, 1)
print('patched during_drop useVk')

# Normalize empty action -> r BEFORE action handlers; remove bad fallthrough
marker = "            if ($action -eq 'g') {"
inject = '''            if (-not $tunnelSyncOk -and $action -eq '') {
                Write-ConnectLog 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
                $action = 'r'
            }

'''
if "SESSION: fallthrough_recover reason=tunnel_down_empty_action" in c and inject.strip() in c:
    print('inject already near top? will still clean duplicate block')
elif marker not in c:
    raise SystemExit('action=g marker missing')
else:
    # Only inject once before first action=g after session key loop
    # Find the one after during_drop block
    pos = c.find("SESSION_KEY ignore non_command(during_drop)")
    if pos < 0:
        raise SystemExit('during_drop log missing')
    gpos = c.find(marker, pos)
    if gpos < 0:
        raise SystemExit('action=g after drop not found')
    if 'fallthrough_recover reason=tunnel_down_empty_action' not in c[gpos-400:gpos]:
        c = c[:gpos] + inject + c[gpos:]
        print('injected normalize empty->r')
    else:
        print('normalize already injected')

# Remove the incomplete fallthrough recover block after action=q
old_ft = '''            if (-not $tunnelSyncOk) {
                # Tunnel drop with no usable key — recover (same as action=r auto path).
                Write-ConnectLog 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
                $action = 'r'
                $skipRecoveryClear = [bool]($editorOpened -or $script:EditorSeenOpen)
                Begin-ConnectRecovery -Trigger 'auto' -ProjectId $go.Id -EditorWasOpen $skipRecoveryClear
                if ($skipRecoveryClear) {
                    Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open' 'WARN'
                    $alreadyDown = $false
                } else {
                    Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop -Reason 'auto_recovery'
                    Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                    $alreadyDown = $true
                }
                $script:LaptopSshVerified = $false
                continue sessionLoop
            }

            Write-ConnectLog ("SESSION: ignore_empty_action gotKey={0} tunnel={1}" -f $gotKey, $tunnelSyncOk) 'WARN'
            continue sessionLoop
'''
# try both dash variants
if old_ft not in c:
    old_ft2 = old_ft.replace('—', '-')
    if old_ft2 in c:
        old_ft = old_ft2
    else:
        # softer match
        start = c.find("            if (-not $tunnelSyncOk) {\n                # Tunnel drop")
        if start < 0:
            start = c.find("SESSION: fallthrough_recover reason=tunnel_down_empty_action")
            # find the if block that contains incomplete recover AFTER action=q
            q = c.find("reason=user_quit")
            start = c.find("            if (-not $tunnelSyncOk)", q)
        if start < 0:
            print('WARN: incomplete fallthrough block not found (maybe already removed)')
        else:
            end = c.find("            Write-ConnectLog (\"SESSION: ignore_empty_action", start)
            if end < 0:
                raise SystemExit('ignore_empty_action not found')
            end2 = c.find('\n', c.find('continue sessionLoop', end)) + 1
            c = c[:start] + '''            Write-ConnectLog ("SESSION: ignore_empty_action gotKey={0} tunnel={1}" -f $gotKey, $tunnelSyncOk) 'WARN'
            continue sessionLoop
''' + c[end2:]
            print('removed incomplete fallthrough via span')
else:
    c = c.replace(old_ft, '''            Write-ConnectLog ("SESSION: ignore_empty_action gotKey={0} tunnel={1}" -f $gotKey, $tunnelSyncOk) 'WARN'
            continue sessionLoop
''', 1)
    print('removed incomplete fallthrough exact')

# bump version 26 -> 27
c, n = re.subn(r'20260719\.26', '20260719.27', c)
print(f'connect.ps1 version bumps: {n}')
connect.write_text(c, encoding='utf-8', newline='\n')

# git-mode Read-RetryQuitKey
g = gitmode.read_text(encoding='utf-8')
old_rq = '''        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            $kc2 = $ki2.KeyChar.ToString()
            $ascii2 = ($kc2.Length -eq 1 -and [int][char]$kc2[0] -ge 32 -and [int][char]$kc2[0] -le 126)
            $letter2 = if ($ascii2) { $kc2.ToLowerInvariant() } else { '' }
            # Non-ASCII KeyChar (e.g. Persian ض on physical Q) must NOT map via ConsoleKey.
            if ($letter2 -eq 'r' -or ($letter2 -eq '' -and $ki2.Key -eq [ConsoleKey]::R)) { $rk = 'r' }
            elseif ($letter2 -eq 'q' -or ($letter2 -eq '' -and $ki2.Key -eq [ConsoleKey]::Q)) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {'''

new_rq = '''        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            $kc2 = $ki2.KeyChar.ToString()
            $code2 = if ($kc2.Length -eq 1) { [int][char]$kc2[0] } else { 0 }
            $ascii2 = ($code2 -ge 32 -and $code2 -le 126)
            $letter2 = if ($ascii2) { $kc2.ToLowerInvariant() } else { '' }
            # VK fallback ONLY for null/control KeyChar — never Persian printable non-ASCII.
            $useVk2 = ($code2 -eq 0 -or ($code2 -gt 0 -and $code2 -lt 32))
            if ($letter2 -eq 'r' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::R)) { $rk = 'r' }
            elseif ($letter2 -eq 'q' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::Q)) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {'''

if old_rq not in g:
    raise SystemExit('Read-RetryQuitKey block not found')
g = g.replace(old_rq, new_rq, 1)
g, n2 = re.subn(r'20260719\.26', '20260719.27', g)
print(f'git-mode version bumps: {n2}')
gitmode.write_text(g, encoding='utf-8', newline='\n')
print('patched Read-RetryQuitKey')

for vf in [root/'scripts/client/windows/connect-version.txt', root/'scripts/client/mac/connect-version.txt']:
    vf.write_text('20260719.27', encoding='utf-8', newline='\n')
    print('bumped', vf.name)

mac = root/'scripts/client/mac/connect.sh'
if mac.exists():
    mt = mac.read_text(encoding='utf-8')
    mt2, n3 = re.subn(r'20260719\.26', '20260719.27', mt)
    if n3:
        mac.write_text(mt2, encoding='utf-8', newline='\n')
        print(f'mac bumps {n3}')

print('DONE')
