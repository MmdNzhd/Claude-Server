$ErrorActionPreference='Continue'
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'publish\.ps1|deploy-client|run-full-publish|wait-publish|deploy-smart') })
Write-Output ("procs=" + $procs.Count)
foreach ($p in $procs) {
  $c = $p.CommandLine
  if ($c.Length -gt 140) { $c = $c.Substring(0,140) }
  Write-Output ("  pid=$($p.ProcessId) $c")
}
foreach ($t in @('smart@192.168.210.240','sepidz@192.168.250.70')) {
  try {
    $v = (& ssh -o BatchMode=yes -o ConnectTimeout=8 $t "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null")
    Write-Output ("$t => [$($v.Trim())]")
  } catch {
    Write-Output "$t => ERR $($_.Exception.Message)"
  }
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
