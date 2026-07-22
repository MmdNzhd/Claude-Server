$paths = @(
    'Desktop\Claude-Connect\windows',
    'Desktop\claude-publish\claude-code-client-20260720\windows',
    'Desktop\claude-publish\claude-code-client-20260717\windows'
)

function Test-FileChecks {
    param([string]$Path, [string]$Label)
    Write-Output "=== $Label ==="
    if (-not (Test-Path $Path)) {
        Write-Output 'PATH_MISSING'
        return
    }
    $files = @{
        'connect-version.txt' = @('20260720.22')
        'connect.bat'         = @('Early single-instance gate')
        'connect-ui.ps1'      = @('mutex error (block)', 'AllowEmptyString')
        'git-mode.ps1'        = @('TunnelPid', 'no result line')
        'connect.ps1'         = @('20260720.22', 'TunnelPid')
    }
    foreach ($entry in $files.GetEnumerator()) {
        $fp = Join-Path $Path $entry.Key
        if (-not (Test-Path $fp)) {
            Write-Output "MISSING $($entry.Key)"
            continue
        }
        $c = Get-Content -LiteralPath $fp -Raw
        $bad = @()
        foreach ($pat in $entry.Value) {
            if ($c -notmatch [regex]::Escape($pat)) { $bad += "MISS:$pat" }
        }
        if ($entry.Key -eq 'connect-ui.ps1') {
            if ($c -match 'MULTI_INSTANCE: allowed') { $bad += 'BAD:MULTI_INSTANCE allowed' }
            if ($c -match 'mutex error \(continue\)') { $bad += 'BAD:mutex continue' }
        }
        if ($entry.Key -eq 'git-mode.ps1') {
            if ($c -match '-TunnelPid\s+\$Pid\b') { $bad += 'BAD:TunnelPid uses $Pid' }
        }
        if ($bad.Count -eq 0) {
            Write-Output "OK $($entry.Key)"
        } else {
            Write-Output "FAIL $($entry.Key): $($bad -join ', ')"
        }
    }
}

foreach ($p in $paths) {
    $full = Join-Path $env:USERPROFILE $p
    Test-FileChecks -Path $full -Label $p
}
