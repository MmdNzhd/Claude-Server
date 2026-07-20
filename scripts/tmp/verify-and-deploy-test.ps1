Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fail = 0
function Assert-True([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  OK  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ""
Write-Host "=== Server bundle audit ===" -ForegroundColor White
foreach ($t in @(
        @{L='Smart';S='smart@192.168.210.240';IP='192.168.210.240'},
        @{L='Sepidz';S='smart@192.168.250.70';IP='192.168.250.70'}
    )) {
    Write-Host ""
    Write-Host "$($t.L) ($($t.S))" -ForegroundColor Cyan
    & ssh -o BatchMode=yes -o ConnectTimeout=10 $t.S "echo ok" 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "SSH reachable"
    if ($LASTEXITCODE -ne 0) { continue }

    $ver = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $t.S "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
    $ip = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $t.S "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1").Trim()
    $mountOk = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $t.S "bash -n /usr/local/share/claude-client/mac/claude-mount.sh 2>&1 && echo OK").Trim()

    if ($ver) { Write-Host "  version: v$ver" -ForegroundColor DarkGray } else { Write-Host "  version: MISSING" -ForegroundColor Yellow; $script:fail++ }
    Write-Host "  connect.ps1 IP: $ip" -ForegroundColor DarkGray
    Assert-True ($ip -eq $t.IP) "correct IP in bundle"
    Assert-True ($mountOk -match 'OK') "claude-mount.sh syntax on server"
}

$pubRoot = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$smartDir = Get-ChildItem $pubRoot -Directory -Filter 'claude-code-client-*' | Sort-Object Name -Descending | Select-Object -First 1
$sepidDir = Get-ChildItem $pubRoot -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1
if ($smartDir -and $sepidDir) {
    $pubVer = (Get-Content (Join-Path $smartDir.FullName 'windows\connect-version.txt') -Raw).Trim()
    Write-Host ""
    Write-Host "Published desktop version: v$pubVer" -ForegroundColor DarkGray
}

Write-Host ""
if ($fail -eq 0) { Write-Host "Audit passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail issue(s) found." -ForegroundColor Red
exit 1
