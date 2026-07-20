$ErrorActionPreference = 'Stop'
$fail = 0
function Assert([bool]$cond, [string]$name) {
  if ($cond) { Write-Host "PASS $name" -ForegroundColor Green }
  else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ }
}
$cm = Get-Content scripts\server\claude-mount.sh -Raw
$ps1 = Get-Content scripts\client\windows\connect.ps1 -Raw
$gm = Get-Content scripts\client\git-mode.ps1 -Raw
Assert ($ps1 -match "ConnectVersion = '20260720.8'") 'version 20260720.8'
Assert ($ps1 -match 'FAIL ADMIN_ELEVATE') 'always elevate UAC'
Assert ($ps1 -match 'elevated=') 'logs elevated='
Assert ($gm -match 'Prefer package mac') 'Resolve prefers mac/'
Assert ($ps1 -match 'command not found\|_emit_git') 'path warn ignores command-not-found'
Assert ($cm -match '_emit_git_hide_warn\(\)') 'emit fn in source'
Assert (-not [regex]::IsMatch($cm, '\$\{rpath//''/')) 'no broken rpath quote form'
$safe = @(Select-String -Path scripts\server\claude-mount.sh -Pattern 'local safe=')
Assert ($safe.Count -ge 3) ("safe= lines >=3 (got {0})" -f $safe.Count)
Assert ((@($safe | Where-Object { $_.Line -notmatch "\\'" })).Count -eq 0) 'all safe= escaped'
if ($fail -gt 0) { exit 1 }
Write-Host 'STATIC OK'
