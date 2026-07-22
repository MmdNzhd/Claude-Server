Set-Location D:\Smart\Claude-Code-Server
Write-Host '=== Write-ConnectDecision ==='
$lines = Get-Content scripts/client/connect-ui.ps1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Write-ConnectDecision') {
    for ($j=$i; $j -lt [Math]::Min($i+40,$lines.Count); $j++) { Write-Host ("{0}|{1}" -f ($j+1), $lines[$j]) }
    break
  }
}
Write-Host '=== repo TunnelPid / call ==='
Select-String -Path scripts/client/git-mode.ps1,scripts/client/windows/connect.ps1 -Pattern 'TunnelPid|\[int\]\$Pid|-Pid \$' | ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename,$_.LineNumber,$_.Line.Trim()) }
Write-Host '=== Desktop live pack ==='
$d = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows'
Write-Host "path=$d exists=$(Test-Path $d)"
if (Test-Path $d) {
  Write-Host ("ver=" + (Get-Content (Join-Path $d 'connect-version.txt') -Raw).Trim())
  Select-String -Path (Join-Path $d 'git-mode.ps1') -Pattern '\[int\]\$Pid|TunnelPid' | Select-Object -First 5 | ForEach-Object { Write-Host ("LIVE_GM:{0}:{1}" -f $_.LineNumber,$_.Line.Trim()) }
  Select-String -Path (Join-Path $d 'connect.ps1') -Pattern 'Write-TunnelDropLog|-Pid|-TunnelPid' | Select-Object -First 5 | ForEach-Object { Write-Host ("LIVE_CN:{0}:{1}" -f $_.LineNumber,$_.Line.Trim()) }
}
Write-Host '=== server bundle ver ==='
# via ssh if possible - skip
Write-Host '=== Clear-SessionMount / Stop-RemoteEditor callers ==='
Select-String -Path scripts/client/git-mode.ps1,scripts/client/windows/connect.ps1 -Pattern 'Stop-RemoteEditor|Clear-SessionMount|SkipEditorStop|LAUNCH_KILL' | ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename,$_.LineNumber,$_.Line.Trim()) }
Write-Host '=== proxy mentions ==='
Select-String -Path scripts/client/*.ps1,scripts/client/windows/*.ps1 -Pattern 'proxy|Proxy|HTTP_PROXY|WinHttp|InternetSettings' -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Write-Host ("{0}:{1}:{2}" -f $_.Filename,$_.LineNumber,$_.Line.Trim()) }
Write-Host '=== publish how ==='
Select-String -Path publish/publish.ps1 -Pattern 'Deploy|deploy-client|Bump-Connect' | Select-Object -First 25 | ForEach-Object { Write-Host ("{0}:{1}" -f $_.LineNumber,$_.Line.Trim()) }
