$ErrorActionPreference='Stop'
$gm='D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines=Get-Content $gm
Write-Host ("total="+$lines.Count)
Write-Host '--- around L2172 ---'
for($i=2155;$i -le 2190 -and $i -lt $lines.Count;$i++){ Write-Host ("{0,5}|{1}" -f ($i+1), $lines[$i]) }
Write-Host '--- Add-TunnelHttpProxyLeg ---'
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'function Add-TunnelHttpProxyLeg|function Get-TunnelProxyLegState|function Set-SocksProxyPortOnReuse'){
    Write-Host ("FOUND L$($i+1): $($lines[$i])")
  }
}
# show Add-TunnelHttpProxyLeg full
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match 'function Add-TunnelHttpProxyLeg'){
    for($j=$i;$j -lt [Math]::Min($i+80,$lines.Count);$j++){
      Write-Host ("{0,5}|{1}" -f ($j+1), $lines[$j])
      if($j -gt $i -and $lines[$j] -match '^function '){ break }
    }
    break
  }
}
Write-Host '--- spawn http leg usage ---'
Select-String -Path $gm -Pattern 'Add-TunnelHttpProxyLeg|httpCandidate|HttpProxyPort|missing_http|Get-HttpProxyPort' | ForEach-Object {
  Write-Host ("L$($_.LineNumber): $($_.Line.Trim())")
}
# proper parse
$tokens=$null; $errs=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($gm, [ref]$tokens, [ref]$errs)
Write-Host ("PARSE errs="+$errs.Count)
$errs | Select-Object -First 15 | ForEach-Object { Write-Host $_.ToString() }
$el='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$tokens=$null; $errs=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($el, [ref]$tokens, [ref]$errs)
Write-Host ("EL PARSE errs="+$errs.Count)
$errs | Select-Object -First 15 | ForEach-Object { Write-Host $_.ToString() }
# git-mode.sh syntax via ssh? use python tokenize-ish - just look for function Add or http in sh
$sh='D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
Write-Host '--- sh http markers ---'
Select-String -Path $sh -Pattern 'HTTP_PROXY_PORT|19180|10809|missing_http|xray_server_http|http_proxy_leg' | Select-Object -First 40 | ForEach-Object {
  Write-Host ("L$($_.LineNumber): $($_.Line.Trim())")
}
