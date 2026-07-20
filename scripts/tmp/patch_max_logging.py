# -*- coding: utf-8 -*-
"""Maximize logging coverage: every user input + decision + silent exit paths."""
from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')

# ---- connect-ui.ps1: sync more often (every 5) + Read-ConnectPrompt ----
ui = root / 'scripts/client/connect-ui.ps1'
t = ui.read_text(encoding='utf-8')

t = t.replace(
    '$script:ConnectLogLinesSinceSync -ge 20',
    '$script:ConnectLogLinesSinceSync -ge 5',
)

# Insert Read-ConnectPrompt after Write-ConnectLog function if missing
if 'function Read-ConnectPrompt' not in t:
    helper = r'''
function Read-ConnectPrompt {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Tag = 'INPUT'
    )
    $val = (Read-Host $Prompt)
    $shown = if ($null -eq $val) { '' } else { [string]$val }
    $safe = $shown
    if ($safe.Length -gt 200) { $safe = $safe.Substring(0, 200) + '...' }
    Write-ConnectLog ("{0}: prompt={1} answer={2}" -f $Tag, ($Prompt -replace '\s+', ' ').Trim(), $safe)
    return $val
}

function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog ("DECISION: {0}={1}" -f $What, $Value) $Level
}

'''
    idx = t.find('function Write-ConnectTrace')
    if idx < 0:
        raise SystemExit('Write-ConnectTrace missing')
    t = t[:idx] + helper + t[idx:]
    print('Read-ConnectPrompt added')

ui.write_text(t, encoding='utf-8', newline='\n')
print('connect-ui.ps1 OK')

# ---- connect.ps1: instrument Choose-Project + admin yn + menu keys ----
cp = root / 'scripts/client/windows/connect.ps1'
c = cp.read_text(encoding='utf-8')

# Choose-Project: log menu choice
old = '''        $c = (Read-Host '    >').Trim().ToLower()
        Write-Host ''
        if (-not $c) { continue }
        if ($c -match '^[0-9]+$') {
            $null = ($m = Select-Mount $mounts $c)
            if (-not $m) { Warn "Not found."; continue }
            if (-not (Warn-InvalidProjectRpath -Rpath $m.Rpath -Num $c -Os 'windows')) { continue }
            return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path; Rpath = $m.Rpath })
        }'''
new = '''        $c = (Read-ConnectPrompt '    >' -Tag 'MENU_PROJECT').Trim().ToLower()
        Write-Host ''
        if (-not $c) { Write-ConnectDecision 'project_menu' 'empty_retry'; continue }
        if ($c -match '^[0-9]+$') {
            $null = ($m = Select-Mount $mounts $c)
            if (-not $m) { Write-ConnectDecision 'project_select' "not_found:$c" 'WARN'; Warn "Not found."; continue }
            if (-not (Warn-InvalidProjectRpath -Rpath $m.Rpath -Num $c -Os 'windows')) { Write-ConnectDecision 'project_select' "invalid_rpath:$c"; continue }
            Write-ConnectDecision 'project_select' ("id={0} path={1} rpath={2}" -f $m.Id, $m.Path, $m.Rpath)
            return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path; Rpath = $m.Rpath })
        }'''
if old not in c:
    print('WARN Choose-Project block mismatch')
else:
    c = c.replace(old, new, 1)
    print('Choose-Project OK')

# switch actions
replacements = [
    ('"a" {\n                $null = ($r = Add-Project)',
     '"a" {\n                Write-ConnectDecision \'project_menu\' \'add\'\n                $null = ($r = Add-Project)'),
    ("'e' {\n                $null = ($cur = Select-Mount $mounts (Read-Host '    Edit number').Trim())",
     "'e' {\n                Write-ConnectDecision 'project_menu' 'edit'\n                $null = ($cur = Select-Mount $mounts (Read-ConnectPrompt '    Edit number' -Tag 'MENU_EDIT_NUM').Trim())"),
    ('$nLbl = (Read-Host "    Display name [$($cur.Label)]").Trim(); if (-not $nLbl) { $nLbl = $cur.Label }\n                $nR   = (Read-Host "    Laptop folder [$($cur.Rpath)]").Trim() -replace \'\\\\\',\'/\'; if (-not $nR) { $nR = $cur.Rpath }',
     '$nLbl = (Read-ConnectPrompt "    Display name [$($cur.Label)]" -Tag \'MENU_EDIT_LABEL\').Trim(); if (-not $nLbl) { $nLbl = $cur.Label }\n                $nR   = (Read-ConnectPrompt "    Laptop folder [$($cur.Rpath)]" -Tag \'MENU_EDIT_PATH\').Trim() -replace \'\\\\\',\'/\'; if (-not $nR) { $nR = $cur.Rpath }\n                Write-ConnectDecision \'project_edit\' ("id={0} label={1} rpath={2}" -f $cur.Id, $nLbl, $nR)'),
    ('"d" {\n                $null = ($m = Select-Mount $mounts (Read-Host "    Delete number").Trim())\n                if (-not $m) { Warn "Not found."; continue }\n                if ((Read-Host "    Delete \'$($m.Label)\'? [y/N]").Trim().ToLower() -eq "y") {',
     '"d" {\n                Write-ConnectDecision \'project_menu\' \'delete\'\n                $null = ($m = Select-Mount $mounts (Read-ConnectPrompt "    Delete number" -Tag \'MENU_DEL_NUM\').Trim())\n                if (-not $m) { Warn "Not found."; continue }\n                if ((Read-ConnectPrompt "    Delete \'$($m.Label)\'? [y/N]" -Tag \'MENU_DEL_CONFIRM\').Trim().ToLower() -eq "y") {\n                    Write-ConnectDecision \'project_delete\' $m.Id'),
    ("'c' {\n                Write-Host ''\n                Write-Host '    Configuration' -ForegroundColor White",
     "'c' {\n                Write-ConnectDecision 'project_menu' 'config'\n                Write-Host ''\n                Write-Host '    Configuration' -ForegroundColor White"),
    ("$cfgChoice = (Read-Host '    >').Trim()\n                switch ($cfgChoice) {",
     "$cfgChoice = (Read-ConnectPrompt '    >' -Tag 'MENU_CONFIG').Trim()\n                Write-ConnectDecision 'config_choice' $cfgChoice\n                switch ($cfgChoice) {"),
    ('"g" { Configure-GitMode }\n            "q" { Write-Host ""; exit 0 }',
     '"g" { Write-ConnectDecision \'project_menu\' \'git_mode\'; Configure-GitMode }\n            "q" { Write-ConnectDecision \'project_menu\' \'quit\'; Write-Host ""; exit 0 }'),
]

for old, new in replacements:
    if old not in c:
        print('WARN miss:', old[:70].replace('\n',' '))
    else:
        c = c.replace(old, new, 1)
        print('patched:', old[:40].replace('\n',' '))

# admin yn
old_yn = '''    $yn = (Read-Host '    Allow administrator access? [Y/n]').Trim()'''
new_yn = '''    $yn = (Read-ConnectPrompt '    Allow administrator access? [Y/n]' -Tag 'ADMIN_UAC').Trim()
    Write-ConnectDecision 'admin_access' $yn'''
if old_yn in c:
    c = c.replace(old_yn, new_yn, 1)
    print('admin yn OK')

# setup username
old_ru = '''    $RemoteUser = (Read-Host "    Server username").Trim()'''
new_ru = '''    $RemoteUser = (Read-ConnectPrompt "    Server username" -Tag 'SETUP_USER').Trim()
    Write-ConnectDecision 'setup_remote_user' $RemoteUser'''
if old_ru in c:
    c = c.replace(old_ru, new_ru, 1)
    print('setup user OK')

# session key actions
old_key = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }

                    $gotKey = $true
                    break
                }'''
new_key = '''                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2}" -f $action, $ki.Key, $ki.KeyChar)
                    $gotKey = $true
                    break
                }'''
if old_key in c:
    c = c.replace(old_key, new_key, 1)
    print('session key OK')
else:
    print('WARN session key block')

# after PROJECT log line already exists - ensure Sync after project choose
if "Write-ConnectLog \"PROJECT: id=$($go.Id)" in c and 'Sync-ConnectLogToServer' in c:
    pass

cp.write_text(c, encoding='utf-8', newline='\n')
print('connect.ps1 OK')

# ---- git-mode: Configure-GitMode + foreign session ----
gm = root / 'scripts/client/git-mode.ps1'
g = gm.read_text(encoding='utf-8')

old_choice = '''    $choice = (Read-Host '    >').Trim().ToLower()
    switch ($choice) {
        { $_ -in '1', 'off', '' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'off' -Encoding ASCII | Out-Null
        }
        { $_ -in '2', 'hide', 'fast' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'hide' -Encoding ASCII | Out-Null
        }
        { $_ -in '3', 'on', 'server', 'slow' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'server' -Encoding ASCII | Out-Null
        }
        default { Warn 'Invalid choice.'; return }
    }'''
new_choice = '''    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    >' -Tag 'GIT_MODE').Trim().ToLower()
    } else { (Read-Host '    >').Trim().ToLower() }
    Write-GitModeLog "INTERACTIVE: git_mode_choice=$choice" 'INFO'
    switch ($choice) {
        { $_ -in '1', 'off', '' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'off' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=off' 'INFO'
        }
        { $_ -in '2', 'hide', 'fast' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'hide' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=hide' 'INFO'
        }
        { $_ -in '3', 'on', 'server', 'slow' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'server' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=server' 'INFO'
        }
        default { Write-GitModeLog "DECISION: git_mode_invalid=$choice" 'WARN'; Warn 'Invalid choice.'; return }
    }'''
if old_choice in g:
    g = g.replace(old_choice, new_choice, 1)
    print('Configure-GitMode OK')
else:
    print('WARN git mode choice')

old_foreign = '''    $choice = (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant()'''
new_foreign = '''    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    Continue and take over that session? [y/N]' -Tag 'FOREIGN_SESSION').Trim().ToLowerInvariant()
    } else { (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant() }
    Write-GitModeLog "DECISION: foreign_session_takeover=$choice" 'WARN\''''
# fix quoting error in new_foreign
new_foreign = '''    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    Continue and take over that session? [y/N]' -Tag 'FOREIGN_SESSION').Trim().ToLowerInvariant()
    } else { (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant() }
    Write-GitModeLog "DECISION: foreign_session_takeover=$choice" 'WARN'
'''
if old_foreign in g:
    g = g.replace(old_foreign, new_foreign, 1)
    print('foreign session OK')

gm.write_text(g, encoding='utf-8', newline='\n')
print('git-mode.ps1 OK')

# ---- connect-update: no silent exits ----
cu = root / 'scripts/client/windows/connect-update.ps1'
u = cu.read_text(encoding='utf-8')
u = u.replace(
    "if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { exit 0 }",
    "if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Write-UpdateFileLog 'ssh_missing' 'ERROR'; exit 0 }",
)
u = u.replace(
    "if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { exit 0 }",
    "if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { Write-UpdateFileLog 'scp_missing' 'ERROR'; exit 0 }",
)
u = u.replace(
    "if (-not $manifestRaw) { exit 0 }",
    "if (-not $manifestRaw) { Write-UpdateFileLog 'manifest_empty_or_unreachable' 'ERROR'; exit 0 }",
)
u = u.replace(
    "if ($files.Count -eq 0) { exit 0 }",
    "if ($files.Count -eq 0) { Write-UpdateFileLog 'manifest_zero_files' 'ERROR'; exit 0 }",
)
# log each file apply failure path if exists
if "Write-UpdateFileLog \"manifest_files=$($files.Count)\"" not in u:
    u = u.replace(
        "Write-UpdateMsg '  downloading client bundle...' 'DarkGray'",
        "Write-UpdateFileLog (\"manifest_files=$($files.Count)\")\nWrite-UpdateMsg '  downloading client bundle...' 'DarkGray'",
        1,
    )
cu.write_text(u, encoding='utf-8', newline='\n')
print('connect-update.ps1 OK')

print('ALL MAX LOGGING DONE')
