$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding $false

# Find curly quotes across client scripts
$pat = '[\u201C\u201D\u2018\u2019]'
Get-ChildItem scripts\client -Recurse -Include *.ps1,*.bat,*.sh -EA 0 | ForEach-Object {
  $t = [IO.File]::ReadAllText($_.FullName)
  $m = [regex]::Matches($t, $pat)
  if ($m.Count -gt 0) {
    Write-Host ("CURLY {0} count={1}" -f $_.FullName.Replace((Get-Location).Path+'\',''), $m.Count)
    $idx = $t.IndexOfAny(@([char]0x2018,[char]0x2019,[char]0x201C,[char]0x201D))
    if ($idx -ge 0) {
      $s = $t.Substring([Math]::Max(0,$idx-40), [Math]::Min(100, $t.Length-[Math]::Max(0,$idx-40))) -replace "`r|`n",' '
      Write-Host ("  snip: $s")
    }
  }
}

# Fix pipeline test handoff pattern
$tp = (Resolve-Path 'scripts\client\tests\test-connect-pipeline.ps1').Path
$tt = [IO.File]::ReadAllText($tp)
$old = 'Assert ($connectBat -match ''start "" /D "%HERE%" powershell.*connect-boot\.ps1'') ''connect.bat async handoff starts connect-boot.ps1'''
$new = 'Assert ($connectBat -match ''start "" /D "%HERE_NOTRAIL%" powershell(\.exe)?.*connect-boot\.ps1'') ''connect.bat async handoff starts connect-boot.ps1'''
if ($tt.Contains($old)) {
  [IO.File]::WriteAllText($tp, $tt.Replace($old, $new), $utf8)
  Write-Host 'PIPELINE_HANDOFF_ASSERT_FIXED'
} else {
  # try double-quote form from file
  Write-Host 'old exact not found; trying regex replace'
  $tt2 = [regex]::Replace($tt,
    "Assert \(\`$connectBat -match 'start \"\" /D \"%HERE%\" powershell\.\*connect-boot\\\.ps1'\) '[^']*'",
    "Assert (`$connectBat -match 'start \"\" /D \"%HERE_NOTRAIL%\" powershell(\\.exe)?.*connect-boot\\.ps1') 'connect.bat async handoff starts connect-boot.ps1'")
  if ($tt2 -eq $tt) {
    # read line 148 raw
    $lines = Get-Content $tp
    Write-Host ("L148 RAW: " + $lines[147])
    $lines[147] = 'Assert ($connectBat -match ''start "" /D "%HERE_NOTRAIL%" powershell(\.exe)?.*connect-boot\.ps1'') ''connect.bat async handoff starts connect-boot.ps1'''
    [IO.File]::WriteAllLines($tp, $lines, $utf8)
    Write-Host 'PIPELINE_HANDOFF_LINE_REPLACED'
  } else {
    [IO.File]::WriteAllText($tp, $tt2, $utf8)
    Write-Host 'PIPELINE_HANDOFF_REGEX_FIXED'
  }
}

# Run failing suites with full output to files
$suites = @(
  'test-connect-pipeline.ps1',
  'test-publish.ps1',
  'test-connect-update-fail-exit.ps1'
)
foreach ($s in $suites) {
  Write-Host ("===== RUN $s =====")
  & powershell -NoProfile -ExecutionPolicy Bypass -File ("scripts\client\tests\$s") 2>&1 | Select-Object -Last 50
  Write-Host ("EXIT_$s=$LASTEXITCODE")
}
