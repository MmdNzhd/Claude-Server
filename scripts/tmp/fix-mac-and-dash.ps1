Set-Location 'D:\Smart\Claude-Code-Server'
$ErrorActionPreference='Stop'

# --- fix em-dash and any remaining fancy punct in connect.ps1 ---
$p='scripts\client\windows\connect.ps1'
$t=[IO.File]::ReadAllText($p)
$t2=$t -replace '[\u201C\u201D]','"' -replace '[\u2018\u2019]',"'" -replace '[\u2014\u2013\u2012]','-'
[IO.File]::WriteAllText($p,$t2)
$t3=[IO.File]::ReadAllText($p)
"connect curly=$($t3 -match '[\u201C\u201D\u2018\u2019]') emdash=$($t3 -match '[\u2014\u2013]')"

# --- fix git-mode.sh seq + recover ---
$g='scripts\client\git-mode.sh'
$gs=[IO.File]::ReadAllText($g)
$orig=$gs
# both wait loops
$gs=$gs.Replace('for i in $(seq 1 4); do','for i in $(seq 1 12); do')
# broken recover line - match the mangled pattern
$bad='timeout 30 sshx "$CM recover-one ''$id'' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true'
# file uses single quotes around $id inside double - read actual line
$line=(Select-String -Path $g -Pattern 'recover-one').Line | Where-Object { $_ -match 'timeout 30 sshx' } | Select-Object -First 1
"OLD_RECOVER=$line"
$good='    sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true'
if($line){
  $gs=$gs.Replace($line.TrimStart(), $good.TrimStart())
}
if($gs -eq $orig -and $line){
  # try replace exact line content from file
  $gs=[IO.File]::ReadAllText($g)
  $gs2=[regex]::Replace($gs,
    'timeout 30 sshx "\$CM recover-one ''\$id'' 2>/dev/null \|\| timeout 30 sshx "\$CM recover-if-needed ''\$id'' 2>/dev/null \|\| timeout 30 sshx "\$CM recover" 2>/dev/null \|\| true',
    'sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true')
  if($gs2 -eq $gs){
    # raw from dump: timeout 30 sshx "$CM recover-one '$id' ...
    $gs2=[regex]::Replace($gs,
      'timeout 30 sshx "\$CM recover-one ''\$id''[^`n]+',
      'sshx "timeout 30 $CM recover-one ''$id'' 2>/dev/null || timeout 30 $CM recover-if-needed ''$id'' 2>/dev/null || timeout 30 $CM recover 2>/dev/null" 2>/dev/null || true')
  }
  $gs=$gs2
}
[IO.File]::WriteAllText($g,$gs)
$gs=[IO.File]::ReadAllText($g)
"seq4=$($gs -match 'seq 1 4') seq12=$($gs -match 'seq 1 12')"
$mangle=$gs -match 'timeout 30 sshx "\$CM recover-one.*sshx "\$CM'
"nested_mangle=$mangle"
Select-String -Path $g -Pattern 'recover-one|seq 1 ' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }

# Get-ClientFile path used by tests
$tf='scripts\client\tests\_paths.ps1'
if(Test-Path $tf){ Get-Content $tf }
