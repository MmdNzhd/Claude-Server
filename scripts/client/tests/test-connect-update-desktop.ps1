$ErrorActionPreference = 'Stop'
function Test-VerNewer([string]$Remote, [string]$Local) {
    if ($Remote -match '^(\d{8})\.(\d+)$') {
        $rd = [int]$Matches[1]; $rb = [int]$Matches[2]
        if ($Local -match '^(\d{8})\.(\d+)$') {
            $ld = [int]$Matches[1]; $lb = [int]$Matches[2]
            if ($rd -ne $ld) { return $rd -gt $ld }
            return $rb -gt $lb
        }
    }
    return $Remote -gt $Local
}
Write-Host '=== Windows auto-update smoke ==='
$p = 0; $f = 0
if (Test-VerNewer '20260713.26' '20260713.25') { $p++; Write-Host 'PASS .26 > .25' -ForegroundColor Green } else { $f++; Write-Host 'FAIL .26 > .25' -ForegroundColor Red }
if (-not (Test-VerNewer '20260713.9' '20260713.10')) { $p++; Write-Host 'PASS .9 not > .10' -ForegroundColor Green } else { $f++; Write-Host 'FAIL .9 vs .10' -ForegroundColor Red }
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
if (Test-Path (Join-Path $desk 'connect-update.ps1')) { $p++; Write-Host 'PASS connect-update.ps1 on Desktop' -ForegroundColor Green } else { $f++; Write-Host 'FAIL connect-update.ps1 missing (run sync-desktop.ps1)' -ForegroundColor Red }
$bat = Join-Path $desk 'connect.bat'
if ((Test-Path $bat) -and ((Get-Content $bat -Raw) -match 'connect-update\.ps1')) { $p++; Write-Host 'PASS connect.bat hook' -ForegroundColor Green } else { $f++; Write-Host 'FAIL connect.bat hook' -ForegroundColor Red }
$verFile = Join-Path $desk 'connect-version.txt'
$ps1File = Join-Path $desk 'connect.ps1'
if ((Test-Path $verFile) -and (Test-Path $ps1File)) {
    $v = (Get-Content $verFile -Raw).Trim()
    $ps1 = Get-Content $ps1File -Raw
    if ($ps1 -match "ConnectVersion = '$v'") { $p++; Write-Host "PASS Desktop version sync ($v)" -ForegroundColor Green } else { $f++; Write-Host 'FAIL Desktop version mismatch' -ForegroundColor Red }
}
try {
    $remoteVer = ssh -n -o BatchMode=yes -o ConnectTimeout=5 claude-server 'cat /usr/local/share/claude-client/connect-version.txt' 2>$null
} catch { $remoteVer = $null }
if ($remoteVer) {
    $p++; Write-Host "PASS server bundle v$($remoteVer.Trim())" -ForegroundColor Green
} else {
    Write-Host 'SKIP server bundle not deployed (run: sudo claude-server deploy-client-bundle)' -ForegroundColor Yellow
}
Write-Host ''
if ($f -eq 0) { Write-Host "All $p passed." -ForegroundColor Green; exit 0 }
Write-Host "$f failed, $p passed." -ForegroundColor Red; exit 1
