$ErrorActionPreference = 'Stop'
$exe = 'C:\Users\Smart\Downloads\claude-code-client-20260715.QUARANTINE-DO-NOT-RUN-20260721-214141\windows\Claude-Connect.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  Write-Host ("MISSING: {0}" -f $exe)
  exit 1
}
$item = Get-Item -LiteralPath $exe
Write-Host ("exe={0}" -f $item.FullName)
Write-Host ("bytes={0} mtime={1}" -f $item.Length, $item.LastWriteTime)

# Elevate via RunAs (UAC). If already admin, still launches elevated child.
$p = Start-Process -FilePath $exe -WorkingDirectory $item.DirectoryName -Verb RunAs -PassThru
if (-not $p) {
  Write-Host 'Start-Process returned null'
  exit 1
}
Write-Host ("started pid={0}" -f $p.Id)
# Give SFX a moment to start
Start-Sleep -Seconds 3
try {
  $alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
  if ($alive) { Write-Host ("still_running pid={0}" -f $p.Id) }
  else { Write-Host ("exited exit={0}" -f $p.ExitCode) }
} catch {}

# Show related connect processes
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $cl = [string]$_.CommandLine
  $cl -match 'Claude-Connect' -or $cl -match 'connect-boot\.ps1' -or $cl -match 'connect\.ps1'
} | Select-Object ProcessId, Name, @{n='CL';e={
  $c=[string]$_.CommandLine; if($c.Length -gt 160){$c.Substring(0,160)+'...'} else {$c}
}} | Format-List

Write-Host 'DONE'
