$ErrorActionPreference = 'Continue'
$p = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log'
$lines = Get-Content -LiteralPath $p
$sid = '81668aabcc72'
Write-Output "==== SESSION $sid count ===="
$sess = @($lines | Where-Object { $_ -match $sid })
Write-Output ("n=" + $sess.Count)
$sess | Select-Object -First 15
Write-Output '...'
$sess | Select-Object -Last 25
Write-Output '==== CONNECT PROCS ===='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='cmd.exe'" |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'connect\.ps1|connect\.bat|ClaudeConnect|connect-boot') } |
  ForEach-Object {
    $c = $_.CommandLine
    if ($c.Length -gt 200) { $c = $c.Substring(0,200) }
    Write-Output ("{0} | {1}" -f $_.ProcessId, $c)
  }
Write-Output '==== LOCAL ssh -R ports ===='
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match '-R\s+(\d+):localhost:22' } |
  ForEach-Object {
    [void]($_.CommandLine -match '-R\s+(\d+):localhost:22')
    Write-Output ("pid={0} port={1}" -f $_.ProcessId, $Matches[1])
  }
Write-Output '==== VERSION ===='
Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt'
