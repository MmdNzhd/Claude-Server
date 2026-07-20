$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$t=Get-Content -LiteralPath $p -Raw
$chars=@([char]0x201C,[char]0x201D,[char]0x2018,[char]0x2019)
$i=0
foreach($c in $chars){
  $idx=0
  while(($idx=$t.IndexOf($c,$idx)) -ge 0){
    $i++
    $start=[Math]::Max(0,$idx-40); $len=[Math]::Min(80,$t.Length-$start)
    "CHAR U+{0:X4} at {1}: ...{2}..." -f [int]$c, $idx, ($t.Substring($start,$len) -replace "`r|`n",' ')
    $idx++
    if($i -gt 20){ break }
  }
}
"total=$i match=$($t -match '[\u201C\u201D\u2018\u2019]')"

# push_server_connect_conf || true
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh' -Pattern 'push_server_connect_conf|PUSH_CONF' |
  Select-Object -First 40 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(130,$_.Line.Trim().Length)))" }

# recover_mounts lines
Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh' -Pattern 'recover_mounts_if_needed|recover-one' |
  Select-Object -First 20 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }
