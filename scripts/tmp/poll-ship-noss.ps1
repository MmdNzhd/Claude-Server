$ErrorActionPreference='Continue'
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'publish\.ps1|deploy-client|run-full-publish|wait-publish|deploy-smart') })
Write-Output ("procs=" + $procs.Count)
foreach ($p in $procs) {
  $c = $p.CommandLine
  if ($c.Length -gt 160) { $c = $c.Substring(0,160) }
  Write-Output ("  pid=$($p.ProcessId) $c")
}
$ssh = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue)
Write-Output ("ssh_count=" + $ssh.Count)
foreach ($p in $ssh) {
  $c = if ($p.CommandLine) { $p.CommandLine } else { '' }
  if ($c.Length -gt 140) { $c = $c.Substring(0,140) }
  Write-Output ("  ssh pid=$($p.ProcessId) $c")
}
$pack='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows'
if (Test-Path (Join-Path $pack 'connect-version.txt')) {
  Write-Output ("pack_ver=" + (Get-Content (Join-Path $pack 'connect-version.txt') -Raw).Trim())
  $gm = Join-Path $pack 'git-mode.ps1'
  Write-Output ("pack_nc=" + [bool](Select-String -Path $gm -Pattern 'nc -w 2 127.0.0.1 \$Port' -Quiet))
  Write-Output ("pack_reattach=" + [bool](Select-String -Path $gm -Pattern 'Reattach BEFORE' -Quiet))
  Write-Output ("pack_syncok=" + [bool](Select-String -Path (Join-Path $pack 'connect.ps1') -Pattern 'tunnelSyncOk' -Quiet))
  Write-Output ("pack_diag=" + [bool](Select-String -Path (Join-Path $pack 'connect-diagnostic.ps1') -Pattern 'tunnelEffectivelyUp' -Quiet))
}
# zip exists?
Write-Output ("zip=" + (Test-Path 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717.zip'))
Write-Output ("sepid_dir=" + (Test-Path 'C:\Users\Smart\Desktop\claude-publish\claude-code-sepidz-20260717'))
