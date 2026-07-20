Write-Host '===== Resolve-SessionKey / Map-Key / default action ====='
Select-String -Path 'scripts\client\windows\connect.ps1','scripts\client\connect-ui.ps1' -Pattern 'function Resolve-|function Map-|useVk|DefaultAction|default.?action|Enter.*disconnect|KeyChar|VirtualKeyCode|IgnoreEmpty|fallthrough|Flush|KeyAvailable|Acquire-Connect|SINGLE_INSTANCE|already running|second instance' -CaseSensitive:$false |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host '===== Menu WARN paths ====='
Select-String -Path 'scripts\client\windows\connect.ps1','scripts\client\connect-ui.ps1','scripts\client\lib\*.ps1' -Pattern 'Warn-Invalid|Show-ProjectMenu|Write-Host.*WARN|\[WARN\]|menu' -CaseSensitive:$false |
  Select-Object -First 60 |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)) }

Write-Host '===== docs client-connect Persian/quit/mutex ====='
Select-String -Path 'docs\client-connect.md' -Pattern 'Persian|keyboard|quit|mutex|UAC|elevat|ReadKey|buffer|history|Enter|default' -CaseSensitive:$false |
  ForEach-Object { "{0}:{1}:{2}" -f $_.Filename, $_.LineNumber, $_.Line.Trim().Substring(0,[Math]::Min(160,$_.Line.Trim().Length)) }

Write-Host '===== git log connect.ps1 recent ====='
git log --oneline -40 -- scripts/client/windows/connect.ps1 scripts/client/connect-ui.ps1 scripts/client/mac/connect.sh
