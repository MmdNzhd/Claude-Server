$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$bytes = [IO.File]::ReadAllBytes($p)
# find line 1581 in UTF-8
$textUtf8 = [Text.Encoding]::UTF8.GetString($bytes)
$utf8Lines = $textUtf8 -split "`n"
$L = $utf8Lines[1580]
Write-Output "UTF8_LINE<<$L>>"
$non = @()
for ($i=0; $i -lt $L.Length; $i++) {
  $c=[int][char]$L[$i]
  if ($c -gt 127) { $non += ("pos={0} U+{1:X4}" -f $i,$c) }
}
Write-Output "UTF8_NONASCII:"
$non | ForEach-Object { Write-Output $_ }
# find byte offset of line 1581
$offset = 0
for ($n=0; $n -lt 1580; $n++) {
  $offset += [Text.Encoding]::UTF8.GetByteCount($utf8Lines[$n]) + 1 # approx LF; file may be CRLF
}
# better: scan for unique ASCII substring
$needle = [Text.Encoding]::UTF8.GetBytes('VK fallback ONLY for null/control KeyChar')
$idx = -1
for ($i=0; $i -le $bytes.Length - $needle.Length; $i++) {
  $ok=$true
  for ($j=0; $j -lt $needle.Length; $j++) { if ($bytes[$i+$j] -ne $needle[$j]) { $ok=$false; break } }
  if ($ok) { $idx=$i; break }
}
Write-Output "NEEDLE_IDX=$idx"
if ($idx -ge 0) {
  $slice = $bytes[($idx)..($idx+90)]
  Write-Output ("HEX=" + (($slice | ForEach-Object { $_.ToString('X2') }) -join ' '))
}
# Compare encodings
$default = Get-Content $p -Raw
$utf8gc = Get-Content $p -Raw -Encoding UTF8
Write-Output ("DEFAULT_MATCH_CURLY=" + ($default -match '[\u201C\u201D\u2018\u2019]'))
Write-Output ("UTF8_MATCH_CURLY=" + ($utf8gc -match '[\u201C\u201D\u2018\u2019]'))
# parse still ok?
$parseErrs=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$null,[ref]$parseErrs)
Write-Output ("PARSE_ERR_COUNT=" + $(if($parseErrs){$parseErrs.Count}else{0}))
