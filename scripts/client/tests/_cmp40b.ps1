$ErrorActionPreference = 'Stop'
$desk = 'C:\Users\Smart\Desktop\Claude-Connect\connect.ps1'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$d = [IO.File]::ReadAllText($desk)
$r = [IO.File]::ReadAllText($repo)
$marks = @(
  'RECOVERY_MOUNTOK_REASSERT','ACTIVE_MOUNT_GUARD','RECOVERY_SKIP_CLEAR_MOUNT','FINALLY_KEEP_TUNNEL',
  'Get-RemoteEditorSessionPresence','Begin-ConnectRecovery','FOREIGN_INDETERMINATE',
  'auto_relaunch_skip','AllowPersonal','ClaudeServerCursorProfile-Smart',
  'cursor-profile-db-tool','AUTH_SYNC_SKIP','db_too_large','Invoke-LaptopAdminOps',
  'TrustedTunnel','Ensure-SessionTunnel','tunnelAuthRetryCount','ConnectPerf',
  'session_open_summary','auth_folder_check','Initialize-SessionBgTunnel'
)
Write-Host 'mark | desk | repo'
foreach ($m in $marks) {
  Write-Host ("{0} | {1} | {2}" -f $m, ($d.Contains($m)), ($r.Contains($m)))
}
# version files
foreach ($vf in @(
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt',
  'C:\Users\Smart\Desktop\Claude-Connect\connect-version.txt',
  'D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt'
)) {
  if (Test-Path $vf) { Write-Host ("VERFILE {0} = {1}" -f $vf, (Get-Content $vf -Raw).Trim()) }
}

# Restore desk -> repo with safe string replace for arrows
$utf8 = New-Object System.Text.UTF8Encoding $false
$t2 = $d
foreach ($pair in @(
  @{o=[string][char]0x2018; n="'"},
  @{o=[string][char]0x2019; n="'"},
  @{o=[string][char]0x201C; n='"'},
  @{o=[string][char]0x201D; n='"'},
  @{o=[string][char]0x2192; n='->'},
  @{o=[string][char]0x2190; n='<-'}
)) { $t2 = $t2.Replace($pair.o, $pair.n) }
$t2 = [regex]::Replace($t2, '[\u00C2\u00A0\u00C3\u02DC\u00B6]+', '->')
$t2 = $t2 -replace 'A->A->', '->'
$t2 = $t2 -replace '\(A-> on Q\)', '(arrow glyph on Q)'
$t2 = $t2 -replace '\(-> on Q\)', '(arrow glyph on Q)'
$tmp = $repo + '.tmpfix'
[IO.File]::WriteAllText($tmp, $t2, $utf8)
[IO.File]::Copy($tmp, $repo, $true)
[IO.File]::Delete($tmp)
Write-Host 'COPIED'
$errs=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($repo,[ref]$null,[ref]$errs)
Write-Host ("parse_errs=" + $(if($errs){$errs.Count}else{0}))
$rr=[IO.File]::ReadAllText($repo)
Write-Host ("repo_ver=" + $(if($rr -match "ConnectVersion = '([^']+)'"){$Matches[1]}else{'?'}))
Write-Host ("gc_curly=" + [bool]((Get-Content $repo -Raw) -match '[\u201C\u201D\u2018\u2019]'))
