foreach ($n in @('Global\ClaudeConnect','Global\ClaudeConnect-Smart')) {
  try {
    $m = New-Object System.Threading.Mutex($false, $n)
    if ($m.WaitOne(0)) {
      Write-Output "FREE: $n"
      $m.ReleaseMutex()
      $m.Close()
      $m.Dispose()
    } else {
      Write-Output "HELD: $n"
      $m.Close()
      $m.Dispose()
    }
  } catch {
    Write-Output "ERR: $n $($_.Exception.Message)"
  }
}
Get-CimInstance Win32_Process -Filter "ProcessId=56168 OR ProcessId=31188 OR ProcessId=62496 OR ProcessId=52080" |
  Select-Object ProcessId,Name,CommandLine | Format-List
