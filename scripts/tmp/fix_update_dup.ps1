$ErrorActionPreference='Stop'
$p='scripts\client\windows\connect-update.ps1'
$t=[IO.File]::ReadAllText((Resolve-Path $p))
Write-Host '--- around line 195-210 ---'
$lines=$t -split "`n"
for($i=190;$i -lt 215 -and $i -lt $lines.Count;$i++){ Write-Host ('{0,4}|{1}' -f ($i+1), $lines[$i]) }

if($t -match 'Invoke-BundleDownloadfunction Invoke-BundleDownload'){
  $t=$t.Replace('Invoke-BundleDownloadfunction Invoke-BundleDownload','Invoke-BundleDownload')
  [IO.File]::WriteAllText((Resolve-Path $p), $t)
  Write-Host 'FIXED duplicate header'
} else {
  Write-Host 'pattern variant search...'
  $idx=$t.IndexOf('function Invoke-BundleDownload')
  Write-Host $t.Substring([Math]::Max(0,$idx-80), 200)
}
