$files = @(
  'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh',
  'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
)
foreach ($f in $files) {
  Write-Output "==== $f ===="
  Select-String -Path $f -Pattern '_action=|session_key|push_server_connect_conf|ORPHAN|soft_fail|TunnelSoftFail|CLEAR_MOUNT|pkill' |
    Select-Object -First 40 |
    ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}
Write-Output '=== Mac session loop region ==='
$c = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh'
for ($i=900; $i -le 1050; $i++) { if ($i -le $c.Count) { Write-Output ("{0,4}|{1}" -f $i, $c[$i-1]) } }
Write-Output '=== push_server_connect_conf ==='
$g = Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.sh'
for ($i=0; $i -lt $g.Count; $i++) {
  if ($g[$i] -match '^push_server_connect_conf|^function push_server') {
    for ($j=$i; $j -lt [Math]::Min($i+80,$g.Count); $j++) {
      Write-Output ("{0,4}|{1}" -f ($j+1), $g[$j])
      if ($j -gt $i -and $g[$j] -match '^[a-z_]+\(\)|^function ') { break }
    }
  }
}
