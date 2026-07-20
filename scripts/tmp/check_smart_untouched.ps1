function Get-RemoteVer([string]$Target) {
  $out = Join-Path $env:TEMP ('v-' + ($Target -replace '[^a-z0-9]','') + '.txt')
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no',$Target,"tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt") -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
  if (-not $p.WaitForExit(15000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $out -Raw -EA SilentlyContinue)+'').Trim()
}
Write-Host ('Smart=' + (Get-RemoteVer 'smart@192.168.210.240'))
Write-Host ('Sepidz=' + (Get-RemoteVer 'sepidz@192.168.250.70'))
