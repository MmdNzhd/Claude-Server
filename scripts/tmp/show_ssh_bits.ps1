$ErrorActionPreference='Continue'
function Show-Range($path, $start, $end) {
  $lines = Get-Content $path
  for ($i=$start-1; $i -lt $end -and $i -lt $lines.Count; $i++) {
    Write-Host ('{0,4}|{1}' -f ($i+1), $lines[$i])
  }
}
Write-Host '===== connect.ps1 SshX / Invoke-SshXCore ====='
Select-String -Path scripts\client\windows\connect.ps1 -Pattern 'function SshX|function Invoke-SshX|ControlMaster|ClearAllForwardings' |
  ForEach-Object { Write-Host ("{0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
Show-Range scripts\client\windows\connect.ps1 567 620

Write-Host ''
Write-Host '===== git-mode Warn-Foreign + Push ====='
Show-Range scripts\client\git-mode.ps1 819 895

Write-Host ''
Write-Host '===== mac connect.sh mux ====='
Select-String -Path scripts\client\mac\connect.sh -Pattern 'ControlMaster|ControlPath|ControlPersist' |
  Select-Object -First 15 |
  ForEach-Object { "{0}: {1}" -f $_.LineNumber, $_.Line.Trim() }

Write-Host ''
Write-Host '===== version ====='
Write-Host (Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
Select-String -Path scripts\client\windows\connect.ps1 -Pattern "ConnectVersion = '" | Select-Object -First 1
