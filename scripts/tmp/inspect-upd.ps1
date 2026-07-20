$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
$raw = [IO.File]::ReadAllText($p)
$i = $raw.IndexOf('function Get-ServerEndpoint')
Write-Host "index=$i crlf=$($raw.Contains([char]13))"
$chunk = $raw.Substring($i, [Math]::Min(700, $raw.Length - $i))
$lines = $chunk -split "`n" | Select-Object -First 22
foreach ($l in $lines) {
    $hasCr = $l.EndsWith([char]13)
    $t = $l.TrimEnd([char]13)
    Write-Host ("CR={0} LEN={1} | {2}" -f $hasCr, $t.Length, $t)
}
