$ErrorActionPreference = 'Continue'
Write-Host '=== VERSION ==='
Get-Content scripts\client\windows\connect-version.txt
(Select-String -Path scripts\client\windows\connect.ps1 -Pattern "ConnectVersion = '" | Select-Object -First 1).Line

$cm = Get-Content scripts\server\claude-mount.sh -Raw
$ps1 = Get-Content scripts\client\windows\connect.ps1 -Raw
$gm = Get-Content scripts\client\git-mode.ps1 -Raw

$fail = 0
function Assert([bool]$cond, [string]$name) {
  if ($cond) { Write-Host "PASS $name" -ForegroundColor Green }
  else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ }
}

Assert ($ps1 -match "ConnectVersion = '20260720.8'") 'version 20260720.8'
Assert ($ps1 -match 'FAIL ADMIN_ELEVATE') 'always elevate UAC'
Assert ($ps1 -match 'elevated=') 'logs elevated= yes/no'
Assert ($gm -match 'Prefer package mac') 'Resolve prefers mac/'
Assert ($ps1 -match 'command not found\|_emit_git') 'path warn ignores command not found'
Assert ($cm -match '_emit_git_hide_warn\(\)') 'emit fn defined in source'
Assert (-not ($cm -match "\$\{rpath//'/'")) 'no broken ${rpath//''/} form'
$safe = Select-String -Path scripts\server\claude-mount.sh -Pattern 'local safe='
Assert ($safe.Count -ge 3) 'safe= lines present'
Assert (($safe | Where-Object { $_.Line -notmatch "\\'" }).Count -eq 0) 'all safe= use escaped quotes'

Write-Host '=== HARD SUITE ==='
& powershell -NoProfile -File scripts\client\tests\test-hard-multi-agent-regressions.ps1
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host '=== SESSION CONTRACTS ==='
& powershell -NoProfile -File scripts\client\tests\test-session-log-contracts.ps1
if ($LASTEXITCODE -ne 0) { $fail++ }

Write-Host '=== LIVE SERVER ==='
$live = ssh -o BatchMode=yes -o ConnectTimeout=10 smart@192.168.210.240 "bash -n ~/.local/bin/claude-mount && echo bash_n_ok; python3 -c \"t=open('/home/smart/.local/bin/claude-mount').read(); print('broken', t.count(chr(36)+'{rpath//'+chr(39)+'/'+chr(39)+chr(39)+'}')); print('escaped', t.count(r\\\"\\\${rpath//\\\\'/\\\\'\\\\'}\\\"));\"; awk '/^case /{exit}{print}' ~/.local/bin/claude-mount > /tmp/cmf.sh; bash -c 'source /tmp/cmf.sh; declare -F _emit_git_hide_warn >/dev/null && echo EMIT_OK || echo EMIT_MISSING'; \$HOME/.local/bin/claude-mount check deploy; echo check=\$?"
Write-Host $live
if ($live -notmatch 'EMIT_OK') { Write-Host 'FAIL live emit'; $fail++ } else { Write-Host 'PASS live emit' -ForegroundColor Green }
if ($live -notmatch 'bash_n_ok') { $fail++ }

Write-Host ''
if ($fail -eq 0) { Write-Host 'HARD10 VERIFY: ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "HARD10 VERIFY: $fail FAILURES" -ForegroundColor Red; exit 1
