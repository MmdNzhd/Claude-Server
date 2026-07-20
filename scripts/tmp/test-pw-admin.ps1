$Server = 'sepidz@192.168.250.70'
foreach ($pw in @('Admin', 'admin', 'Sepidz@Admin')) {
    $outFile = Join-Path $env:TEMP "pw-$pw.out"
    Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8',$Server,"bash -lc ""echo '$pw' | sudo -S whoami 2>&1""") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile | Out-Null
    $o = Get-Content $outFile -Raw
    Write-Host "$pw => $($o.Trim())"
    if ($o -match '^root$' -or $o -match 'whoami') { if ($o -notmatch 'Sorry') { Write-Host 'MAYBE OK' } }
}
