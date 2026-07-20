$ErrorActionPreference = 'Continue'
$root = 'D:\Smart\Claude-Code-Server'

Write-Host '======== LOCAL FOLDERS ========'
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
Get-ChildItem $pub -Directory -Filter 'claude-code-sepidz-*' -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
  $win = Join-Path $_.FullName 'claude-code\windows'
  $verFile = Join-Path $win 'connect-version.txt'
  $ps1 = Join-Path $win 'connect.ps1'
  $v = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { 'NO_VER_FILE' }
  $embedded = ''
  $ip = ''
  if (Test-Path $ps1) {
    $raw = Get-Content $ps1 -Raw
    $m = [regex]::Match($raw, "ConnectVersion\s*=\s*'([^']+)'")
    if ($m.Success) { $embedded = $m.Groups[1].Value }
    $im = [regex]::Match($raw, '192\.168\.\d+\.\d+')
    if ($im.Success) { $ip = $im.Value }
  }
  Write-Host ("{0}  verFile={1}  embedded={2}  ip={3}  mtime={4}" -f $_.Name, $v, $embedded, $ip, $_.LastWriteTime.ToString('s'))
}

$userPath = 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows'
Write-Host "`n======== USER PATH ========"
Write-Host "exists=$(Test-Path $userPath)"
if (Test-Path $userPath) {
  $vf = Join-Path $userPath 'connect-version.txt'
  Write-Host ("verFile={0}" -f $(if(Test-Path $vf){(Get-Content $vf -Raw).Trim()}else{'missing'}))
  $raw = Get-Content (Join-Path $userPath 'connect.ps1') -Raw
  $m = [regex]::Match($raw, "ConnectVersion\s*=\s*'([^']+)'")
  Write-Host ("embedded={0}" -f $(if($m.Success){$m.Groups[1].Value}else{'?'}))
  $ips = [regex]::Matches($raw, '192\.168\.\d+\.\d+') | ForEach-Object { $_.Value } | Select-Object -Unique
  Write-Host ("ips={0}" -f ($ips -join ','))
}

Write-Host "`n======== connect-update.ps1 KEY LINES ========"
$upd = Join-Path $root 'scripts\client\windows\connect-update.ps1'
Select-String -Path $upd -Pattern 'version|Server|192\.168|scp|ssh|bundle|remote|Download|Update' |
  Select-Object -First 50 | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }

function SshT([string]$Target, [string]$Cmd, [int]$Sec=20) {
  $o = [IO.Path]::GetTempFileName()
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=10',$Target,$Cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError "$o.err"
  if (-not $p.WaitForExit($Sec*1000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -EA SilentlyContinue)+'').Trim()
}

Write-Host "`n======== SEPIDZ LIVE ========"
Write-Host (SshT 'sepidz@192.168.250.70' 'cat /usr/local/share/claude-client/connect-version.txt')
Write-Host (SshT 'sepidz@192.168.250.70' "grep -oE ""ConnectVersion = '[^']+'"" /usr/local/share/claude-client/connect.ps1 | head -1")
Write-Host (SshT 'sepidz@192.168.250.70' "grep -oE '192\\.168\\.[0-9]+\\.[0-9]+' /usr/local/share/claude-client/connect.ps1 | sort -u")

Write-Host "`n======== SMART LIVE ========"
Write-Host (SshT 'smart@192.168.210.240' 'cat /usr/local/share/claude-client/connect-version.txt')
Write-Host (SshT 'smart@192.168.210.240' "grep -oE ""ConnectVersion = '[^']+'"" /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1")

Write-Host "`n======== REPO ========"
Write-Host ((Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim())
