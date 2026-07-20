function Show-Range($path, $start, $end) {
  Write-Host "===== $path :$start-$end ====="
  $i=0
  Get-Content $path | ForEach-Object {
    $i++
    if ($i -ge $start -and $i -le $end) { "{0,5}|{1}" -f $i, $_ }
  }
}
Show-Range 'scripts\client\windows\connect.ps1' 1 50
Show-Range 'scripts\client\windows\connect.ps1' 300 380
Show-Range 'scripts\client\windows\connect.ps1' 1520 1760
Show-Range 'scripts\client\connect-ui.ps1' 60 120
Show-Range 'scripts\client\connect-ui.ps1' 640 760
Show-Range 'scripts\client\mac\connect.sh' 900 1080
