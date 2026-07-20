$p = Join-Path (Get-Location) 'scripts/client/windows/connect.ps1'
$bytes = [IO.File]::ReadAllBytes($p)
$text = [Text.Encoding]::UTF8.GetString($bytes)
# Common smart/curly punctuation that breaks PS 5.1
$codes = @(
  0x2018,0x2019,0x201A,0x201B,0x201C,0x201D,0x201E,0x201F,
  0x2032,0x2033,0x00AB,0x00BB,0x2013,0x2014,0x2026,0x00A0
)
$hits = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $text.Length; $i++) {
  $c = [int][char]$text[$i]
  if ($codes -contains $c) {
    $line = 1
    for ($j = 0; $j -lt $i; $j++) { if ($text[$j] -eq "`n") { $line++ } }
    $snippet = $text.Substring([Math]::Max(0,$i-20), [Math]::Min(40, $text.Length - [Math]::Max(0,$i-20))) -replace "`r|`n",' '
    $hits.Add(("L{0} U+{1:X4} near: {2}" -f $line, $c, $snippet))
  }
}
if ($hits.Count -eq 0) { 'NO_SMART_PUNCT' } else { $hits | Select-Object -First 30; "COUNT=$($hits.Count)" }
