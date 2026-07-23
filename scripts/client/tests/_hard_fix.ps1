$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

# 1) Find curly apostrophe U+2019 in connect.ps1
$cp = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$raw = [IO.File]::ReadAllText($cp)
$idx = $raw.IndexOf([char]0x2019)
Write-Host ("curly_count=" + ([regex]::Matches($raw, [char]0x2019).Count))
if ($idx -ge 0) {
  $snip = $raw.Substring([Math]::Max(0,$idx-60), [Math]::Min(140, $raw.Length - [Math]::Max(0,$idx-60)))
  Write-Host ("SNIP: " + ($snip -replace "`r|`n",' '))
  $fixed = $raw.Replace([char]0x2019, "'")
  # also other curly quotes if any
  $fixed = $fixed.Replace([char]0x2018, "'").Replace([char]0x201C, '"').Replace([char]0x201D, '"')
  [IO.File]::WriteAllText($cp, $fixed, $utf8)
  Write-Host ("after_curly=" + ([regex]::Matches([IO.File]::ReadAllText($cp), [char]0x2019).Count))
}

# 2) Fix test-connect-pipeline async handoff expect HERE_NOTRAIL + powershell.exe
$tp = (Resolve-Path 'scripts\client\tests\test-connect-pipeline.ps1').Path
$tt = [IO.File]::ReadAllText($tp)
Write-Host '--- pipeline asserts mentioning connect-boot / HERE ---'
Select-String -Path $tp -Pattern 'connect-boot|HERE|async|handoff|curly|smart.quote|2019' | ForEach-Object {
  Write-Host ("{0}: {1}" -f $_.LineNumber, $_.Line.Trim())
}
