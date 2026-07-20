$ErrorActionPreference='Continue'
function Get-RemoteVer([string]$Target) {
  $out = Join-Path $env:TEMP ("ver-" + ($Target -replace '[^a-z0-9]','') + ".txt")
  $err = "$out.err"
  $p = Start-Process -FilePath ssh -ArgumentList @(
    '-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',
    $Target, "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt"
  ) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit(15000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + '').Trim()
}
Write-Host ("Sepidz=" + (Get-RemoteVer 'sepidz@192.168.250.70'))
Write-Host ("Smart=" + (Get-RemoteVer 'smart@192.168.210.240'))
