$ErrorActionPreference = 'Stop'
$files = @(
  'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
)
foreach ($f in $files) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    Write-Host ("FAIL {0}" -f $f)
    $errs | ForEach-Object { Write-Host $_.ToString() }
    exit 1
  }
  Write-Host ("OK {0}" -f (Split-Path $f -Leaf))
}
