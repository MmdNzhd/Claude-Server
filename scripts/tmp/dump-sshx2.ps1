$files = @(
  'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1',
  'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1'
)
foreach ($p in $files) {
  $lines = Get-Content -LiteralPath $p
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'function SshX\b') {
      Write-Output "FILE=$p START=$($i+1)"
      for ($j = $i; $j -lt [Math]::Min($i+100, $lines.Count); $j++) {
        Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
        if ($j -gt $i -and $lines[$j] -match '^function ') { break }
      }
    }
  }
}
