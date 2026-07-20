$ErrorActionPreference='Stop'
. .\scripts\client\connect-ui.ps1
. .\scripts\client\git-mode.ps1
Write-Host 'parse_ok'
# prove $HOME stays literal in ship-style concat
$remoteTmp = '.claude/logs/.connect-upd-1.tmp'
$remoteDay = '.claude/logs/connect-20260719.log'
$cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '"; true'
if ($cat -match 'C:\\Users') { throw 'HOME expanded!' }
if ($cat -notmatch '\$HOME/') { throw 'HOME missing' }
Write-Host ('cat_ok=' + $cat.Substring(0,60))
Write-Host ('ver=' + (Get-Content .\scripts\client\windows\connect-version.txt -Raw).Trim())
if (-not (Get-Command Invoke-ConnectLogProcTimed -EA SilentlyContinue)) { throw 'timed helper missing' }
Write-Host 'helper_ok'
# connect-update dots? just parse syntax via Tokenizer
$errs=$null; $tok=$null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\scripts\client\windows\connect-update.ps1), [ref]$tok, [ref]$errs) | Out-Null
if ($errs -and $errs.Count -gt 0) { $errs | ForEach-Object { Write-Host $_.ToString() }; throw 'update parse fail' }
Write-Host 'update_parse_ok'
