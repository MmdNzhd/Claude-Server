from pathlib import Path
root = Path(r'D:/Smart/Claude-Code-Server')

def write(p, text):
    p.write_text(text, encoding='utf-8', newline='\n')

# --- connect-ui.ps1 ---
ui_path = root / 'scripts/client/connect-ui.ps1'
ui = ui_path.read_text(encoding='utf-8')

# Write-ConnectDecision
old_sig = """function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog (\"DECISION: {0}={1}\" -f $What, $Value) $Level
}"""
new_sig = """function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if ($null -eq $Value) { $Value = '' }
    Write-ConnectLog (\"DECISION: {0}={1}\" -f $What, $Value) $Level
}"""

# normalize CRLF for match
ui_n = ui.replace('\r\n', '\n')
if 'AllowEmptyString()' in ui_n and 'function Write-ConnectDecision' in ui_n:
    print('SKIP Decision already has AllowEmptyString')
elif old_sig.replace('\r\n','\n') in ui_n:
    ui_n = ui_n.replace(old_sig.replace('\r\n','\n'), new_sig)
    print('OK Decision')
else:
    # looser replace on Mandatory Value line only
    import re
    m = re.search(r'function Write-ConnectDecision\s*\{.*?^\}', ui_n, re.M|re.S)
    if not m:
        raise SystemExit('Decision function not found')
    block = m.group(0)
    block2 = block.replace(
        '[Parameter(Mandatory)][string]$Value,',
        "[Parameter(Mandatory)][AllowEmptyString()][string]$Value = '',"
    )
    if 'if ($null -eq $Value)' not in block2:
        block2 = block2.replace(
            'Write-ConnectLog ("DECISION:',
            'if ($null -eq $Value) { $Value = \'\' }\n    Write-ConnectLog ("DECISION:'
        )
    if block2 == block:
        print('BLOCK:\n', block[:400])
        raise SystemExit('Decision patch failed')
    ui_n = ui_n[:m.start()] + block2 + ui_n[m.end():]
    print('OK Decision loose')

# Status line
old_st = """    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    Write-Host $line -ForegroundColor DarkCyan
    $statusKey = \"$ProjectLabel|$GitLabel|$tunnel|$ed\"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-ConnectLog \"STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]\"
    }"""
new_st = """    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    $statusKey = \"$ProjectLabel|$GitLabel|$tunnel|$ed\"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-Host $line -ForegroundColor DarkCyan
        Write-ConnectLog \"STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]\"
    }"""
if 'Write-Host $line -ForegroundColor DarkCyan\n    $statusKey' in ui_n:
    ui_n = ui_n.replace(old_st, new_st)
    print('OK status dedupe')
elif 'LastSessionStatusKey = $statusKey\n        Write-Host $line' in ui_n:
    print('SKIP status already fixed')
else:
    # regex
    import re
    pat = re.compile(
        r"(    \$line = \('    \[\{0\} \| git:\{1\} \| tunnel:\{2\} \| \{3\}\]' -f \$ProjectLabel, \$GitLabel, \$tunnel, \$ed\)\n)"
        r"    Write-Host \$line -ForegroundColor DarkCyan\n"
        r"(    \$statusKey = .*?\n)"
        r"    if \(\$statusKey -ne \$script:LastSessionStatusKey\) \{\n"
        r"        \$script:LastSessionStatusKey = \$statusKey\n"
        r"        (Write-ConnectLog .*?\n)"
        r"    \}",
        re.S
    )
    def repl(m):
        return (m.group(1) + m.group(2) +
                "    if ($statusKey -ne $script:LastSessionStatusKey) {\n"
                "        $script:LastSessionStatusKey = $statusKey\n"
                "        Write-Host $line -ForegroundColor DarkCyan\n"
                "        " + m.group(3) +
                "    }")
    ui2, n = pat.subn(repl, ui_n, count=1)
    if n != 1:
        # show context
        idx = ui_n.find('Update-SessionStatusLine')
        print(ui_n[idx:idx+800])
        raise SystemExit('status patch failed')
    ui_n = ui2
    print('OK status regex')

write(ui_path, ui_n)

# --- git-mode Clear-SessionMount ---
gm_path = root / 'scripts/client/git-mode.ps1'
gm = gm_path.read_text(encoding='utf-8').replace('\r\n','\n')
import re
m = re.search(r'function Clear-SessionMount\s*\{.*?\n\}', gm, re.S)
if not m:
    raise SystemExit('Clear-SessionMount not found')
block = m.group(0)
print('--- Clear-SessionMount head ---')
print('\n'.join(block.splitlines()[:40]))
if '[switch]$StopEditor' not in block:
    block2 = block
    if '[switch]$SkipEditorStop' in block2 and '[switch]$StopEditor' not in block2:
        block2 = block2.replace('[switch]$SkipEditorStop,', '[switch]$SkipEditorStop,\n        [switch]$StopEditor,')
        if '[switch]$StopEditor' not in block2:
            block2 = block2.replace('[switch]$SkipEditorStop', '[switch]$SkipEditorStop,\n        [switch]$StopEditor')
    # change if condition
    block2 = block2.replace(
        'if (-not $SkipEditorStop -and $EditorCmd -and $Alias -and $RemotePath)',
        'if ($StopEditor -and -not $SkipEditorStop -and $EditorCmd -and $Alias -and $RemotePath)'
    )
    if block2 == block:
        raise SystemExit('Clear-SessionMount patch no change')
    gm = gm[:m.start()] + block2 + gm[m.end():]
    write(gm_path, gm)
    print('OK Clear-SessionMount StopEditor opt-in')
else:
    print('SKIP Clear-SessionMount already StopEditor')

# --- connect.ps1 ---
win_path = root / 'scripts/client/windows/connect.ps1'
win = win_path.read_text(encoding='utf-8').replace('\r\n','\n')
changed = False
# finally clear without editor stop
for a,b in [
    ("Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path\n                Write-Host \"    Laptop folder restored.\"",
     "Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop -Reason 'session_end'\n                Write-Host \"    Laptop folder restored.\""),
    ("Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -Reason 'user_quit'",
     "Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -SkipEditorStop -Reason 'user_quit'"),
    ("Write-ConnectDecision 'ssh_username_fix' $fix",
     "Write-ConnectDecision 'ssh_username_fix' ([string]$fix)"),
]:
    if a in win:
        win = win.replace(a,b)
        changed = True
        print('OK replace:', a[:60])
    else:
        print('MISS:', a[:60])
if changed:
    write(win_path, win)
print('done')
