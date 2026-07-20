foreach ($path in @(
  'scripts/client/windows/connect.ps1',
  'scripts/client/git-mode.ps1',
  'scripts/client/connect-ui.ps1'
)) {
  $i = 0
  Get-Content $path | ForEach-Object {
    $i++
    if ($_ -match 'Write-ConnectLog\s+' -and $_ -notmatch "'(INFO|WARN|ERROR|DEBUG|TRACE)'" -and $_ -notmatch 'function Write-ConnectLog') {
      $t = $_.Trim()
      if ($t.Length -gt 110) { $t = $t.Substring(0,110) }
      '{0}:{1}:{2}' -f $path, $i, $t
    }
  }
}
