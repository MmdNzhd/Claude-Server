$ErrorActionPreference='Continue'
$files=@(
 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',
 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.sh',
 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',
 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
)
foreach($f in $files){
  Write-Host "==== $f ===="
  $lines=Get-Content $f
  Write-Host ("lines="+$lines.Count+" size="+((Get-Item $f).Length))
  # syntax-ish corruption signals
  $bad=@()
  if($f -match '\.ps1$'){
    $bad += @($lines | Select-String -Pattern '^\s*fi\s*$|^\s*local |function get_|#!/bin/bash|EOF' | Select-Object -First 20)
  } else {
    $bad += @($lines | Select-String -Pattern '^\s*function |Write-Host |\$script:|param\(' | Select-Object -First 20)
  }
  if($bad.Count -eq 0){ Write-Host 'no cross-language markers in sample' }
  else { Write-Host 'CROSS_LANG_MARKERS:'; $bad | ForEach-Object { Write-Host ("  L$($_.LineNumber): $($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))") } }
}
# specifically Clear-CursorProxySettings body
Write-Host '==== Clear-CursorProxySettings region ps1 ===='
$el=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
for($i=0;$i -lt $el.Count;$i++){
  if($el[$i] -match 'function Clear-CursorProxySettings'){
    for($j=$i;$j -lt [Math]::Min($i+40,$el.Count);$j++){ Write-Host ("{0,5}|{1}" -f ($j+1), $el[$j]) }
    break
  }
}
Write-Host '==== set_cursor_proxy_settings region sh ===='
$sh=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.sh'
for($i=0;$i -lt $sh.Count;$i++){
  if($sh[$i] -match 'set_cursor_proxy_settings'){
    for($j=$i;$j -lt [Math]::Min($i+80,$sh.Count);$j++){ Write-Host ("{0,5}|{1}" -f ($j+1), $sh[$j]) }
    break
  }
}
# powershell parse check
Write-Host '==== PS parse editor-launch.ps1 ===='
try {
  $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1',[ref]$null,[ref]$errs)
  if($errs -and $errs.Count){ Write-Host "PARSE_ERRORS=$($errs.Count)"; $errs | Select-Object -First 10 | ForEach-Object { Write-Host $_.ToString() } }
  else { Write-Host 'PARSE_OK' }
} catch { Write-Host "PARSE_EX $($_.Exception.Message)" }
Write-Host '==== PS parse git-mode.ps1 ===='
try {
  $errs=$null
  $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',[ref]$null,[ref]$errs)
  if($errs -and $errs.Count){ Write-Host "PARSE_ERRORS=$($errs.Count)"; $errs | Select-Object -First 10 | ForEach-Object { Write-Host $_.ToString() } }
  else { Write-Host 'PARSE_OK' }
} catch { Write-Host "PARSE_EX $($_.Exception.Message)" }
Write-Host '==== bash -n editor-launch.sh ===='
bash -n 'D:/Smart/Claude-Code-Server/scripts/client/editor-launch.sh' 2>&1 | Select-Object -First 20
Write-Host '==== bash -n git-mode.sh ===='
bash -n 'D:/Smart/Claude-Code-Server/scripts/client/git-mode.sh' 2>&1 | Select-Object -First 20
