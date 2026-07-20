from pathlib import Path
p = Path('scripts/client/tests/test-connect-pipeline.ps1')
t = p.read_text(encoding='utf-8')
block = r'''

# Session ID + silent update-on-drop contracts
Assert ($bat -match 'CLAUDE_CONNECT_RUN_ID') 'connect.bat sets CLAUDE_CONNECT_RUN_ID'
Assert ($ui -match 'Get-ConnectSessionId') 'connect-ui.ps1 Get-ConnectSessionId'
Assert ($ui -match 'sessions\.index') 'connect-ui.ps1 sessions.index'
Assert ($ui -match 'SESSION_FILTER') 'connect-ui.ps1 SESSION_FILTER'
Assert ($ui -match 'Invoke-ConnectSilentUpdateCheck') 'connect-ui.ps1 silent update'
Assert ($ui -match 'UPDATE_SILENT') 'connect-ui.ps1 UPDATE_SILENT'
Assert ($winConnect -match 'Invoke-ConnectSilentUpdateCheck') 'connect.ps1 hooks silent update'
Assert ($winConnect -match 'TUNNEL_DROP reason=auto_reconnect') 'connect.ps1 structured TUNNEL_DROP'
$macSh = Get-Content (Join-Path $root 'mac\connect.sh') -Raw -ErrorAction SilentlyContinue
$uiSh = Get-Content (Join-Path $root 'connect-ui.sh') -Raw -ErrorAction SilentlyContinue
Assert ($macSh -match 'CLAUDE_CONNECT_RUN_ID') 'mac connect.sh exports RUN_ID'
Assert ($uiSh -match 'invoke_connect_silent_update_check') 'connect-ui.sh silent update'
Assert ($uiSh -match 'SESSION_FILTER') 'connect-ui.sh SESSION_FILTER'
Assert ($uiSh -match 'sessions\.index|write_connect_session_index') 'connect-ui.sh sessions.index'
$gitSh = Get-Content (Join-Path $root 'git-mode.sh') -Raw -ErrorAction SilentlyContinue
Assert ($gitSh -match 'invoke_connect_silent_update_check') 'git-mode.sh auto silent update'
'''
if 'Invoke-ConnectSilentUpdateCheck' in t and 'SESSION_FILTER' in t:
    print('tests already have asserts')
else:
    # insert before final summary if possible
    if 'All tests passed' in t:
        # find last Assert before summary
        marker = "# ---- summary"
        if marker not in t:
            # append before end
            t = t.rstrip() + '\n' + block + '\n'
        else:
            t = t.replace(marker, block + '\n' + marker, 1)
        p.write_text(t, encoding='utf-8', newline='\n')
        print('patched pipeline tests')
    else:
        # write dedicated contract file
        Path('scripts/client/tests/test-session-log-contracts.ps1').write_text('''# test-session-log-contracts.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $root 'scripts\\client\\connect-ui.ps1'))) {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..\\..\\..') | Select-Object -ExpandProperty Path
}
$client = Join-Path $root 'scripts\\client'
if (-not (Test-Path (Join-Path $client 'connect-ui.ps1'))) { $client = Join-Path $PSScriptRoot '..' | Resolve-Path }
$failed = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green }
    else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:failed++ }
}
$ui = Get-Content (Join-Path $client 'connect-ui.ps1') -Raw
$bat = Get-Content (Join-Path $client 'windows\\connect.bat') -Raw
$win = Get-Content (Join-Path $client 'windows\\connect.ps1') -Raw
$uiSh = Get-Content (Join-Path $client 'connect-ui.sh') -Raw
$mac = Get-Content (Join-Path $client 'mac\\connect.sh') -Raw
$gitSh = Get-Content (Join-Path $client 'git-mode.sh') -Raw
Assert ($bat -match 'CLAUDE_CONNECT_RUN_ID') 'bat RUN_ID'
Assert ($ui -match 'Get-ConnectSessionId') 'Get-ConnectSessionId'
Assert ($ui -match 'sessions\\.index') 'sessions.index'
Assert ($ui -match 'SESSION_FILTER') 'SESSION_FILTER'
Assert ($ui -match 'Invoke-ConnectSilentUpdateCheck') 'silent update fn'
Assert ($win -match 'Trigger -eq .auto.' -or $win -match "Trigger -eq 'auto'") 'auto trigger'
Assert ($win -match 'Invoke-ConnectSilentUpdateCheck') 'win hooks silent'
Assert ($win -match 'TUNNEL_DROP reason=auto_reconnect') 'TUNNEL_DROP'
Assert ($mac -match 'CLAUDE_CONNECT_RUN_ID') 'mac RUN_ID'
Assert ($uiSh -match 'invoke_connect_silent_update_check') 'mac silent'
Assert ($uiSh -match 'SESSION_FILTER') 'mac SESSION_FILTER'
Assert ($gitSh -match 'invoke_connect_silent_update_check') 'git silent'
if ($failed -gt 0) { Write-Host "FAILED $failed"; exit 1 }
Write-Host 'All session-log contracts passed' -ForegroundColor Green
''', encoding='utf-8', newline='\n')
        print('wrote test-session-log-contracts.ps1')

# Fix client path detection - simplify
client_guess = Path('scripts/client')
Path('scripts/client/tests/test-session-log-contracts.ps1').write_text(r'''# test-session-log-contracts.ps1 - session id + silent update source contracts
$ErrorActionPreference = 'Stop'
$client = Resolve-Path (Join-Path $PSScriptRoot '..')
$failed = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green }
    else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:failed++ }
}
$ui = Get-Content (Join-Path $client 'connect-ui.ps1') -Raw
$bat = Get-Content (Join-Path $client 'windows\connect.bat') -Raw
$win = Get-Content (Join-Path $client 'windows\connect.ps1') -Raw
$uiSh = Get-Content (Join-Path $client 'connect-ui.sh') -Raw
$mac = Get-Content (Join-Path $client 'mac\connect.sh') -Raw
$gitSh = Get-Content (Join-Path $client 'git-mode.sh') -Raw
Assert ($bat -match 'CLAUDE_CONNECT_RUN_ID') 'bat RUN_ID'
Assert ($ui -match 'Get-ConnectSessionId') 'Get-ConnectSessionId'
Assert ($ui -match 'sessions\.index') 'sessions.index'
Assert ($ui -match 'SESSION_FILTER') 'SESSION_FILTER'
Assert ($ui -match 'Invoke-ConnectSilentUpdateCheck') 'silent update fn'
Assert ($win -match 'Invoke-ConnectSilentUpdateCheck') 'win hooks silent'
Assert ($win -match 'TUNNEL_DROP reason=auto_reconnect') 'TUNNEL_DROP'
Assert ($mac -match 'CLAUDE_CONNECT_RUN_ID') 'mac RUN_ID'
Assert ($uiSh -match 'invoke_connect_silent_update_check') 'mac silent'
Assert ($uiSh -match 'SESSION_FILTER') 'mac SESSION_FILTER'
Assert ($gitSh -match 'invoke_connect_silent_update_check') 'git silent'
if ($failed -gt 0) { Write-Host "FAILED $failed"; exit 1 }
Write-Host 'All session-log contracts passed' -ForegroundColor Green
''', encoding='utf-8', newline='\n')
print('contracts written')
