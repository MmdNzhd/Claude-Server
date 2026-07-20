$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$lines = Get-Content $p
$lineNum = 1581
$line = $lines[$lineNum-1]
Write-Output "LINE_NUM=$lineNum"
Write-Output "LINE_LEN=$($line.Length)"
Write-Output "RAW_LINE<<$line>>"
$sb = New-Object System.Text.StringBuilder
for ($i=0; $i -lt $line.Length; $i++) {
  $c = [int][char]$line[$i]
  if ($c -gt 127 -or $c -in 0x201C,0x201D,0x2018,0x2019) {
    [void]$sb.AppendFormat("pos={0} U+{1:X4} char=[{2}]`n", $i, $c, $line[$i])
  }
}
Write-Output "NON_ASCII:"
Write-Output $sb.ToString()
# surrounding lines
for ($n=$lineNum-2; $n -le $lineNum+2; $n++) {
  if ($n -ge 1 -and $n -le $lines.Count) {
    Write-Output ("L{0}: {1}" -f $n, $lines[$n-1])
  }
}
# re-run assert logic alone for clarity
$src = Get-Content $p -Raw
$fail = ($src -match '[\u201C\u201D\u2018\u2019]')
Write-Output ("ASSERT_WOULD_FAIL=$fail")
