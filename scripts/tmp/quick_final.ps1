$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$root = 'D:\Smart\Claude-Code-Server'

Write-Host 'LOCAL harden:'
$items = @(
  @{ N = 'deploy base64'; Ok = [bool](Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern 'base64, non-interactive' -Quiet) },
  @{ N = 'no old hang'; Ok = -not [bool](Select-String -Path "$root\publish\deploy-client-bundles.ps1" -Pattern '\$SudoPassword \| & ssh' -Quiet) },
  @{ N = 'git policy'; Ok = [bool](Select-String -Path "$root\scripts\server\claude-mount.sh" -Pattern '_apply_git_scm_policy' -Quiet) },
  @{ N = 'update msg'; Ok = [bool](Select-String -Path "$root\scripts\client\windows\connect-update.ps1" -Pattern 'Client up to date' -Quiet) },
  @{ N = 'dle crlf'; Ok = [bool](Select-String -Path "$root\scripts\server\commands\deploy-laptop-exec.sh" -Pattern 'sed -i' -Quiet) },
  @{ N = 'sudoers sepidz'; Ok = [bool](Select-String -Path "$root\scripts\server\sudoers.d\claude-client-deploy" -Pattern 'Defaults:sepidz' -Quiet) }
)
$bad = 0
foreach ($i in $items) {
  if ($i.Ok) { Write-Host "OK  $($i.N)" } else { Write-Host "FAIL $($i.N)"; $bad++ }
}

Write-Host 'VERSIONS:'
Write-Host -NoNewline 'SMART='; ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt'; Write-Host ''
Write-Host -NoNewline 'SEPIDZ='; ssh -o BatchMode=yes -o ConnectTimeout=8 sepidz@192.168.250.70 'cat /usr/local/share/claude-client/connect-version.txt'; Write-Host ''
Write-Host ('REPO=' + (Get-Content "$root\scripts\client\windows\connect-version.txt" -Raw).Trim())

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

$syspy = @(
  'print("MOUNT_POLICY", open("/usr/local/lib/claude-mount").read().count("_apply_git_scm_policy"))',
  'print("LE_CR", open("/usr/local/bin/laptop-exec","rb").read().count(b"\r"))',
  'print("VER", open("/usr/local/share/claude-client/connect-version.txt").read().strip())'
) -join "`n"
[IO.File]::WriteAllText("$env:TEMP\syscheck.py", $syspy)
& scp -o BatchMode=yes -q "$env:TEMP\syscheck.py" 'sepidz@192.168.250.70:/tmp/syscheck.py'
& scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz_io_retest.py' 'sepidz@192.168.250.70:/tmp/sepidz_io_retest.py'

$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/syscheck.py' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sepidz_io_retest.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\qf2_wrap.sh", $wrap)
& scp -o BatchMode=yes -q "$env:TEMP\qf2_wrap.sh" 'sepidz@192.168.250.70:/tmp/qf2_wrap.sh'
Write-Host 'SEPIDZ SYS+IO:'
& ssh -o BatchMode=yes -o ConnectTimeout=120 sepidz@192.168.250.70 'bash /tmp/qf2_wrap.sh'
Write-Host "remote_exit=$LASTEXITCODE local_fail=$bad"
if ($bad -ne 0 -or $LASTEXITCODE -ne 0) { exit 1 }
Write-Host 'ALL_GREEN'
