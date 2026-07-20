$ErrorActionPreference='Stop'
foreach ($f in @('scripts\client\windows\connect.ps1','scripts\client\git-mode.ps1','scripts\client\connect-ui.ps1')) {
  $e=$null;$t=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f),[ref]$t,[ref]$e)
  if ($e -and $e.Count) { $e|%{$_.ToString()}; throw "fail $f" }
  Write-Host "parse_ok $f"
}
if (Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'ControlMaster=auto' -Quiet) { throw 'mux still present' }
if (-not (Select-String -Path scripts\client\git-mode.ps1 -Pattern 'skip_duplicate' -Quiet)) { throw 'dedupe missing' }
if (-not (Select-String -Path scripts\client\git-mode.ps1 -Pattern 'one SSH reads conf' -Quiet)) { throw 'warn batch missing' }
if (-not (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'attempt -le 3' -Quiet)) { throw 'update retry broken' }
Write-Host 'VERIFY_OK'
