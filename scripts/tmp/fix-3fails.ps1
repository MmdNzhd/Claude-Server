#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-Location D:\Smart\Claude-Code-Server
$utf8 = New-Object System.Text.UTF8Encoding $false

# 1) Remove em-dash U+2014 from connect.ps1 comment
$winPath = Resolve-Path 'scripts/client/windows/connect.ps1'
$win = [IO.File]::ReadAllText($winPath)
$win2 = $win.Replace([char]0x2014, '-')
$win2 = $win2.Replace([char]0x2013, '-')
$win2 = $win2.Replace([char]0x201C, '"').Replace([char]0x201D, '"')
$win2 = $win2.Replace([char]0x2018, "'").Replace([char]0x2019, "'")
if ($win2 -ne $win) {
  [IO.File]::WriteAllText($winPath, $win2, $utf8)
  Write-Host 'OK removed smart dashes/quotes from connect.ps1' -ForegroundColor Green
} else {
  Write-Host 'WARN no smart chars replaced in connect.ps1' -ForegroundColor Yellow
}

# 2) Update pipeline timeout assert to new base64|timeout 45 bash pattern
$pipePath = Resolve-Path 'scripts/client/tests/test-connect-pipeline.ps1'
$pipe = [IO.File]::ReadAllText($pipePath)
$old = "Assert (`$winConnect -match 'timeout 45 bash -lc') 'connect.ps1 wraps SshX with timeout'"
$new = "Assert (`$winConnect -match 'timeout 45 bash') 'connect.ps1 wraps SshX with timeout'"
if ($pipe.Contains("timeout 45 bash -lc")) {
  $pipe2 = $pipe.Replace($old, $new)
  if ($pipe2 -eq $pipe) {
    $pipe2 = $pipe.Replace("timeout 45 bash -lc", "timeout 45 bash")
  }
  [IO.File]::WriteAllText($pipePath, $pipe2, $utf8)
  Write-Host 'OK pipeline SshX timeout assert' -ForegroundColor Green
} else {
  Write-Host 'SKIP pipeline timeout assert already updated' -ForegroundColor Yellow
}

# 3) Designer Mac: call enter_connect_single_instance if sourced, or source connect-ui and call
$desPath = Resolve-Path 'scripts/client/users/designer/connect.sh'
$des = [IO.File]::ReadAllText($desPath)
if ($des -notmatch 'enter_connect_single_instance') {
  # Find a good insertion point after SCRIPT_DIR / early bootstrap
  # Look for how main mac connect does it
  Write-Host '--- mac connect.sh single instance call ---'
  Select-String -Path scripts/client/mac/connect.sh -Pattern 'enter_connect_single_instance' | ForEach-Object {
    Write-Host ("MAC:{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
  }
  Write-Host '--- designer connect.sh head ---'
  Get-Content $desPath | Select-Object -First 80 | ForEach-Object -Begin {$i=1} -Process { Write-Host ("{0}|{1}" -f $i, $_); $i++ }
} else {
  Write-Host 'OK designer already has enter_connect_single_instance' -ForegroundColor Green
}
