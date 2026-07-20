$ErrorActionPreference='Continue'

function Show-Range($path, $start, $end) {
  $lines = Get-Content $path
  Write-Output ("---- {0} lines {1}-{2} ----" -f (Split-Path $path -Leaf), $start, $end)
  for ($i=$start; $i -le [Math]::Min($end,$lines.Count); $i++) {
    Write-Output ("{0,5}|{1}" -f $i, $lines[$i-1])
  }
}

# Find key symbols with line numbers in git-mode and connect
foreach ($f in @(
  'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
)) {
  Write-Output ("==== HITS $f ====")
  Select-String -Path $f -Pattern 'function\s+\S*[Tt]unnel|TUNNEL_UP|local_port_open|TunnelBanner|Test-Tunnel|Get-TunnelBanner|orphanssh|Orphan|ACTIVE_MOUNT|TUNNEL_DOWN|SESSION_STATUS|connection dropped|bg_alive|Ensure-Tunnel' |
    ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}

$gm='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$gl=Get-Content $gm
Write-Output '==== ALL functions in git-mode.ps1 ===='
for($i=0;$i -lt $gl.Count;$i++){
  if($gl[$i] -match '^\s*function\s+'){ Write-Output ("{0}:{1}" -f ($i+1), $gl[$i].Trim()) }
}

# Heuristic: find Ensure-Tunnel / Test-Tunnel / Banner function starts and dump ~80 lines
$names=@('Ensure-Tunnel','Test-Tunnel','Get-Tunnel','TunnelBanner','Test-TunnelUp','Get-TunnelBanner','Sync-Tunnel','Clear-Mount','Push-ServerConnectConf')
foreach($name in $names){
  $m = Select-String -Path $gm -Pattern ("function\s+$name\b") | Select-Object -First 1
  if($m){
    Show-Range $gm $m.LineNumber ($m.LineNumber+90)
  }
}

# connect.ps1 diagnostic tunnel fields
$cp='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
Write-Output '==== connect.ps1 TUNNEL/VERDICT hits ===='
Select-String -Path $cp -Pattern 'local_port_open|TUNNEL up=|TUNNEL_DOWN|VERDICT_CODE|Write-Diagnostic|Test-Tunnel|banner' |
  Select-Object -First 50 |
  ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }

# find Write-Diagnostic or similar and dump
foreach($pat in @('function\s+Write-.*Diag','function\s+.*Diagnostic','function\s+Get-Session','VERDICT_CODE\s*=')) {
  $hits=Select-String -Path $cp -Pattern $pat | Select-Object -First 5
  foreach($h in $hits){ Write-Output ("CP_HIT $($h.LineNumber): $($h.Line.Trim())") }
}
