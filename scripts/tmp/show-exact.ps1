$gm='scripts\client\git-mode.ps1'
$lines=Get-Content $gm
28..45 | ForEach-Object { $l=$lines[$_-1]; '[{0}] {1}' -f $_, ([regex]::Escape($l)) }
# Also check raw for CRLF
$bytes=[IO.File]::ReadAllBytes((Resolve-Path $gm))
$crlf=0; $lf=0
for($i=0;$i -lt $bytes.Length;$i++){ if($bytes[$i]-eq 10){ if($i -gt 0 -and $bytes[$i-1]-eq 13){$crlf++}else{$lf++}}}
"crlf_lines=$crlf lf_only=$lf"
