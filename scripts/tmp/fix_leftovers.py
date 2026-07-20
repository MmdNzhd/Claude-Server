from pathlib import Path
import re

# fix leftover boot exits
cp = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
c = cp.read_text(encoding='utf-8')
c = c.replace(
    'if ($boot.Error) { StepFail $boot.Error; Warn "Tip: confirm server username with: connect.bat -Setup"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }',
    'if ($boot.Error) { StepFail $boot.Error; Warn "Tip: confirm server username with: connect.bat -Setup"; Wait-ConnectExit -Reason "boot_error:$($boot.Error)" -Code 1 }',
    1,
)
c = c.replace(
    "if (-not $boot.Ok) { StepFail ($script:pendingFixes -join ', '); Read-Host \"    Press Enter to close\" | Out-Null; exit 1 }",
    "if (-not $boot.Ok) { StepFail ($script:pendingFixes -join ', '); Wait-ConnectExit -Reason 'boot_not_ok' -Code 1 }",
    1,
)
left = [L.strip() for L in c.splitlines() if 'Read-Host' in L and 'Press Enter' in L]
print('leftover', left)
cp.write_text(c, encoding='utf-8', newline='\n')

# fix Launch-RemoteEditor - read function start
el = Path(r'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1')
et = el.read_text(encoding='utf-8')
# Find if we broke it
idx = et.find('function Launch-RemoteEditor')
snippet = et[idx:idx+400]
print('Launch snippet:\n', snippet[:350])
# If log is before param, move it after param block
bad = '''function Launch-RemoteEditor {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }
    param('''
if bad in et:
    et = et.replace(bad, '''function Launch-RemoteEditor {
    param(''', 1)
    # insert after param block closing )
    # find first ) after param( that closes param - then { body
    # simpler: after param block's closing paren and before first real statement
    # Look for pattern after our broken fix - restore and insert after params properly
    m = re.search(r'function Launch-RemoteEditor \{\n    param\((.*?)\)\n', et, re.S)
    if not m:
        raise SystemExit('cannot find Launch-RemoteEditor param')
    insert_at = m.end()
    inject = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }
'''
    if 'LAUNCH begin' not in et[insert_at:insert_at+200]:
        et = et[:insert_at] + inject + et[insert_at:]
    el.write_text(et, encoding='utf-8', newline='\n')
    print('Launch-RemoteEditor fixed')
elif 'LAUNCH begin' in et:
    print('Launch already OK or different shape')
else:
    # add properly
    m = re.search(r'function Launch-RemoteEditor \{\n    param\((.*?)\)\n', et, re.S)
    if m:
        inject = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }
'''
        et = et[:m.end()] + inject + et[m.end():]
        el.write_text(et, encoding='utf-8', newline='\n')
        print('Launch injected OK')
    else:
        print('WARN Launch pattern not found')

# mac cfg_choice
mc = Path(r'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh')
m = mc.read_text(encoding='utf-8')
old = "read -rp '    > ' cfg_choice"
new = 'if declare -F connect_prompt >/dev/null 2>&1; then cfg_choice="$(connect_prompt "    > " "MENU_CONFIG")"; else read -rp "    > " cfg_choice; fi\n                    if declare -F connect_decision >/dev/null 2>&1; then connect_decision config_choice "$cfg_choice"; fi'
if old in m:
    m = m.replace(old, new, 1)
    mc.write_text(m, encoding='utf-8', newline='\n')
    print('cfg_choice OK')
else:
    print('cfg_choice already or missing', 'connect_prompt' in m and 'MENU_CONFIG' in m)

print('fix leftovers done')
