Set-Location 'D:\Smart\Claude-Code-Server'
$utf8=New-Object System.Text.UTF8Encoding $false

function Scrub-File([string]$rel){
  $path=(Resolve-Path $rel).Path
  $t=[IO.File]::ReadAllText($path)
  $n=([regex]::Matches($t,'[\u201C\u201D\u2018\u2019\u2014\u2013\u2012]')).Count
  $t2=$t -replace '[\u201C\u201D]','"' -replace '[\u2018\u2019]',"'" -replace '[\u2014\u2013\u2012]','-'
  if($t2 -ne $t){ [IO.File]::WriteAllText($path,$t2,$utf8) }
  "$rel scrubbed=$n remaining=$(([regex]::Matches([IO.File]::ReadAllText($path),'[\u201C\u201D\u2018\u2019\u2014\u2013]')).Count)"
}

# scrub all hot client files
Get-ChildItem scripts\client -Recurse -Include *.ps1,*.sh |
  Where-Object { $_.FullName -notmatch '\\tests\\' } |
  ForEach-Object {
    $rel=$_.FullName.Substring((Resolve-Path .).Path.Length+1)
    Scrub-File $rel
  } | Where-Object { $_ -match 'scrubbed=[1-9]' }

Write-Output '=== curly after ==='
foreach($f in @('scripts\client\windows\connect.ps1','scripts\client\connect-ui.ps1','scripts\client\git-mode.ps1')){
  $t=[IO.File]::ReadAllText($f)
  "$f curly=$($t -match '[\u201C\u201D\u2018\u2019]') em=$($t -match '[\u2014\u2013]')"
}

Write-Output '=== mount Remove-Item / .git danger ==='
Select-String -Path scripts\server\claude-mount.sh -Pattern 'Remove-Item|\.git' |
  Where-Object { $_.Line -match 'rm |Remove|\.git' } |
  Select-Object -First 30 |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }

Write-Output '=== CR strip in mount ==='
Select-String -Path scripts\server\claude-mount.sh,scripts\server\claude-automount.sh,scripts\server\claude-watchdog.sh -Pattern '_load_global|tr -d|\\\\r|\\r' |
  Select-Object -First 25 |
  ForEach-Object { "$($_.Filename):$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))" }

Write-Output '=== EditorSeenOpen sticky ==='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'EditorSeenOpen' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)))" }
