# -*- coding: utf-8 -*-
from pathlib import Path

p = Path('scripts/client/connect-ui.ps1')
t = p.read_text(encoding='utf-8')

fn = r'''
function Invoke-ConnectSilentUpdateCheck {
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return }

    $cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
    $stateFile = Join-Path $cfgDir '.last-update-check'
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $lastCheck = 0
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $raw = (Get-Content -LiteralPath $stateFile -Raw -ErrorAction Stop).Trim()
            if ($raw -match '^\d+$') { $lastCheck = [int]$raw }
        } catch { }
    }

    $ageSec = if ($lastCheck -gt 0) { $now - $lastCheck } else { [int]::MaxValue }
    $ageMin = if ($ageSec -ge 0 -and $ageSec -lt [int]::MaxValue) { [int][Math]::Floor($ageSec / 60.0) } else { 0 }

    if ($lastCheck -gt 0 -and $ageSec -lt 1800) {
        Write-ConnectLog "UPDATE_SILENT skip reason=throttle age_min=$ageMin" 'DEBUG'
        return
    }

    $scriptDir = $null
    if ($script:ConnectScriptDir) { $scriptDir = $script:ConnectScriptDir }
    elseif ($PSScriptRoot) { $scriptDir = $PSScriptRoot }
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

    $updateScript = Join-Path $scriptDir 'connect-update.ps1'
    $exitCode = 1
    $result = 'fail'
    $pendingRestart = 0
    $level = 'ERROR'

    try {
        if (-not (Test-Path -LiteralPath $updateScript)) {
            Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 reason=no_script path=$updateScript" 'ERROR'
        } else {
            & $updateScript -ScriptDir $scriptDir -Quiet
            if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE } else { $exitCode = 0 }

            switch ($exitCode) {
                0 { $result = 'ok'; $level = 'INFO' }
                1 { $result = 'fail'; $level = 'ERROR' }
                2 { $result = 'applied'; $pendingRestart = 1; $level = 'WARN' }
                default { $result = 'fail'; $level = 'ERROR' }
            }
            Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=$result exit=$exitCode pending_restart=$pendingRestart" $level
        }
    } catch {
        Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 error=$($_.Exception.Message)" 'ERROR'
    } finally {
        try {
            $null = New-Item -ItemType Directory -Force -Path $cfgDir
            [System.IO.File]::WriteAllText($stateFile, [string]$now, [System.Text.UTF8Encoding]::new($false))
        } catch {
            Write-ConnectLog "UPDATE_SILENT stamp_fail error=$($_.Exception.Message)" 'ERROR'
        }
    }
}

'''

if 'function Invoke-ConnectSilentUpdateCheck' in t:
    print('ALREADY_PRESENT')
else:
    # insert before Write-ConnectSessionOpenSummary or Close-ConnectLog
    anchor = 'function Write-ConnectSessionOpenSummary {'
    if anchor not in t:
        anchor = 'function Close-ConnectLog {'
    if anchor not in t:
        raise SystemExit('NO_ANCHOR')
    t = t.replace(anchor, fn + anchor, 1)
    p.write_text(t, encoding='utf-8', newline='\n')
    print('RESTORED')

# Verify connect.ps1 still hooks
cp = Path('scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
print('connect.ps1 hook', 'Invoke-ConnectSilentUpdateCheck' in cp)
print('auto branch', "Trigger -eq 'auto'" in cp)

# Fix session contract to use exit that works when dot-sourced - use return vs exit
# And fix pipeline to capture failures
pipe = Path('scripts/client/tests/test-connect-pipeline.ps1')
pt = pipe.read_text(encoding='utf-8')
# If it dotsources session contracts, make sure failure propagates
if 'test-session-log-contracts.ps1' in pt and 'sessionLogFailed' not in pt:
    # replace bare dot-source with tracked failure
    old = ". (Join-Path $PSScriptRoot 'test-session-log-contracts.ps1')"
    # try variants
    import re
    m = re.search(r"\. \(Join-Path \$PSScriptRoot ['\"]test-session-log-contracts\.ps1['\"]\)", pt)
    if not m:
        m = re.search(r"&\s*\(Join-Path \$PSScriptRoot ['\"]test-session-log-contracts\.ps1['\"]\)", pt)
    if m:
        print('pipeline dotsource at', m.group(0))
    else:
        # find how it's included
        for i,l in enumerate(pt.splitlines(),1):
            if 'session-log' in l:
                print(f'{i}:{l}')

# Fix contracts file: use throw or set exitcode for parent
cpath = Path('scripts/client/tests/test-session-log-contracts.ps1')
ct = cpath.read_text(encoding='utf-8')
# Ensure it matches function name correctly
if "Assert ($ui -match 'Invoke-ConnectSilentUpdateCheck')" not in ct:
    print('contract pattern odd')
print('ui now has fn', 'function Invoke-ConnectSilentUpdateCheck' in p.read_text(encoding='utf-8'))
