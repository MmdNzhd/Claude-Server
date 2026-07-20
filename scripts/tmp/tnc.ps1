foreach ($ip in @('192.168.210.240','192.168.250.70')) {
  $r = Test-NetConnection -ComputerName $ip -Port 22 -WarningAction SilentlyContinue
  Write-Host ("{0} Ping={1} Tcp={2}" -f $ip, $r.PingSucceeded, $r.TcpTestSucceeded)
}
# Also try System.Net.Sockets
foreach ($ip in @('192.168.210.240','192.168.250.70')) {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect($ip, 22, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(5000, $false)
    if (-not $ok) { Write-Host "$ip SocketConnect=TIMEOUT"; $c.Close(); continue }
    $c.EndConnect($iar)
    Write-Host "$ip SocketConnect=OK"
    $c.Close()
  } catch { Write-Host "$ip SocketConnect=ERR $($_.Exception.Message)" }
}
