$ErrorActionPreference = 'Stop'
$desk = 'C:\Users\Smart\Desktop\Claude-Connect\connect.ps1'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$d = Get-Content $desk -Raw
$r = Get-Content $repo -Raw
Write-Host ("desk_len=" + $d.Length + " repo_len=" + $r.Length)
foreach ($label in @('desk','repo')) {
  $t = if ($label -eq 'desk') { $d } else { $r }
  $ver = if ($t -match "ConnectVersion = '([^']+)'") { $Matches[1] } else { '?' }
  $marks = @(
    'Get-SiblingConnectTunnelPids',
    'RECOVERY_MOUNTOK_REASSERT',
    'ACTIVE_MOUNT_GUARD',
    'FOREIGN_INDETERMINATE',
    'Begin-ConnectRecovery',
    'Get-RemoteEditorSessionPresence',
    'ORPHAN_TUNNEL',
    'candPort',
    'Get-SessionTunnelPort'
  )
  Write-Host ("--- $label ver=$ver ---")
  foreach ($m in $marks) {
    Write-Host ("  {0}={1}" -f $m, ($t -match [regex]::Escape($m)))
  }
}
# If desk is newer/better, copy to repo
if ($d -match "ConnectVersion = '20260722\.40'") {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  # Normalize: ensure no curly that break tests; fix arrow if any
  $t2 = $d
  $t2 = $t2.Replace([char]0x2018,"'").Replace([char]0x2019,"'")
  $t2 = $t2.Replace([char]0x201C,'"').Replace([char]0x201D,'"')
  $t2 = $t2.Replace([char]0x2192,'->').Replace([char]0x2190,'<-')
  $t2 = [regex]::Replace($t2, '[\u00C2\u00A0\u00C3\u02DC\u00B6]+', '->')
  $t2 = $t2 -replace 'A->A->', '->'
  $t2 = $t2 -replace '\(A-> on Q\)', '(arrow glyph on Q)'
  $t2 = $t2 -replace '\(-> on Q\)', '(arrow glyph on Q)'
  $tmp = $repo + '.tmpfix'
  [IO.File]::WriteAllText($tmp, $t2, $utf8)
  [IO.File]::Copy($tmp, $repo, $true)
  [IO.File]::Delete($tmp)
  Write-Host 'RESTORED_FROM_DESKTOP_TO_REPO'
  $errs=$null
  $null=[System.Management.Automation.Language.Parser]::ParseFile($repo,[ref]$null,[ref]$errs)
  Write-Host ("parse_errs=" + $(if($errs){$errs.Count}else{0}))
  $rr = Get-Content $repo -Raw
  Write-Host ("repo_ver=" + $(if($rr -match "ConnectVersion = '([^']+)'"){$Matches[1]}else{'?'}))
  Write-Host ("gc_curly=" + [bool]($rr -match '[\u201C\u201D\u2018\u2019]'))
}
