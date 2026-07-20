$p = Join-Path (Get-Location) 'scripts/client/windows/connect.ps1'
$bytes = [IO.File]::ReadAllBytes($p)
$text = [Text.Encoding]::UTF8.GetString($bytes)
$curly = @([char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019)
$hits = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $text.Length; $i++) {
  if ($curly -contains $text[$i]) {
    $line = 1
    for ($j = 0; $j -lt $i; $j++) { if ($text[$j] -eq "`n") { $line++ } }
    $hits.Add(("L{0}: U+{1:X4}" -f $line, [int][char]$text[$i]))
  }
}
if ($hits.Count -eq 0) { Write-Output 'PASS: no curly quotes' } else { Write-Output ('FAIL: ' + ($hits -join '; ')) }
