$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1', [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; exit 1 }
'git-mode OK'
$errs2 = $null
[void][System.Management.Automation.Language.Parser]::ParseFile('D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1', [ref]$null, [ref]$errs2)
if ($errs2 -and $errs2.Count) { $errs2 | ForEach-Object { $_.ToString() }; exit 1 }
'connect OK'
# also published copies
$errs3 = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\git-mode.ps1'), [ref]$null, [ref]$errs3)
if ($errs3 -and $errs3.Count) { $errs3 | ForEach-Object { $_.ToString() }; exit 1 }
'launch-tree OK'
