$ErrorActionPreference='Continue'
$pkg=Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260719\claude-code\windows\connect.bat'
$out=Join-Path $env:TEMP 'remote-connect.bat'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','smart@192.168.250.70','cat /usr/local/share/claude-client/connect.bat') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.e')
$null=$p.WaitForExit(15000)

$tp=([IO.File]::ReadAllText($pkg) -replace "`r`n","`n" -replace "`r","`n")
$tr=([IO.File]::ReadAllText($out) -replace "`r`n","`n" -replace "`r","`n")
Write-Host ("pkg_len=$($tp.Length) rem_len=$($tr.Length)")
# char-by-char first diff
$min=[Math]::Min($tp.Length,$tr.Length)
for($i=0;$i -lt $min;$i++){
  if($tp[$i] -ne $tr[$i]){
    $a=[int][char]$tp[$i]; $b=[int][char]$tr[$i]
    Write-Host ("first_char_diff_at=$i pkg_code=$a rem_code=$b")
    $start=[Math]::Max(0,$i-40); $end=[Math]::Min($tp.Length-1,$i+60)
    Write-Host ("pkg_ctx=[" + ($tp.Substring($start, $end-$start+1) -replace "`n",'\n') + "]")
    $end2=[Math]::Min($tr.Length-1,$i+60)
    Write-Host ("rem_ctx=[" + ($tr.Substring($start, $end2-$start+1) -replace "`n",'\n') + "]")
    break
  }
}
if($tp.Length -ne $tr.Length -and $tp.Substring(0,$min) -eq $tr.Substring(0,$min)){
  Write-Host 'prefix equal; length differs at end'
  if($tp.Length -gt $tr.Length){ Write-Host ('pkg_extra=[' + ($tp.Substring($min) -replace "`n",'\n') + ']') }
  else { Write-Host ('rem_extra=[' + ($tr.Substring($min) -replace "`n",'\n') + ']') }
}

# Also compare source bat vs pkg
$src='scripts\client\windows\connect.bat'
$ts=([IO.File]::ReadAllText((Resolve-Path $src)) -replace "`r`n","`n" -replace "`r","`n")
Write-Host ("src_vs_pkg_norm_equal=" + ($ts -eq $tp))
Write-Host ("src_vs_rem_norm_equal=" + ($ts -eq $tr))
# functional markers in remote
foreach($m in @('CLAUDE_CONNECT_RUN_ID','BOOTSTRAP','connect-update.ps1','OUTDATED','ConnectVersion')){
  Write-Host ("rem_has_$m=" + ($tr.Contains($m) -or $tr -match $m))
}
