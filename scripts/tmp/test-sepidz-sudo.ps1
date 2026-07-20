$Server = 'sepidz@192.168.250.70'
foreach ($pw in @('sepidz', 'Admin', 'sepidz@Admin', 'Sepidz@Admin')) {
    Write-Host "Trying password: $pw"
    $cmd = "bash -lc ""echo '$pw' | sudo -S whoami 2>&1"""
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=10 $Server $cmd 2>&1
    $out | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -eq 0) { Write-Host "  SUCCESS with $pw"; break }
}
