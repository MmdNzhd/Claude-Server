$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false

# Curly quote scan + fix in scripts/client
$files = Get-ChildItem scripts\client -Recurse -Include *.ps1,*.bat,*.sh -EA 0
foreach ($f in $files) {
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  # detect UTF8 curly apostrophe E2 80 99
  $has = $false
  for ($i=0; $i -lt $bytes.Length-2; $i++) {
    if ($bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80 -and ($bytes[$i+2] -eq 0x99 -or $bytes[$i+2] -eq 0x98 -or $bytes[$i+2] -eq 0x9C -or $bytes[$i+2] -eq 0x9D)) { $has = $true; break }
  }
  if (-not $has) { continue }
  $t = [IO.File]::ReadAllText($f.FullName)
  $n = ([regex]::Matches($t, '[\u2018\u2019\u201C\u201D]')).Count
  if ($n -eq 0) { continue }
  Write-Host ("CURLY {0} n={1}" -f $f.Name, $n)
  $t2 = $t.Replace([char]0x2018,"'").Replace([char]0x2019,"'").Replace([char]0x201C,'"').Replace([char]0x201D,'"')
  [IO.File]::WriteAllText($f.FullName, $t2, $utf8)
  Write-Host ("FIXED {0}" -f $f.Name)
}

# Fix pipeline test line with HERE_NOTRAIL
$tp = (Resolve-Path 'scripts\client\tests\test-connect-pipeline.ps1').Path
$lines = [IO.File]::ReadAllLines($tp)
for ($i=0; $i -lt $lines.Length; $i++) {
  if ($lines[$i] -match '%HERE%" powershell.*connect-boot') {
    Write-Host ("OLD_LINE {0}: {1}" -f ($i+1), $lines[$i])
    $lines[$i] = 'Assert ($connectBat -match ''start "" /D "%HERE_NOTRAIL%" powershell(\.exe)?.*connect-boot\.ps1'') ''connect.bat async handoff starts connect-boot.ps1'''
    Write-Host ("NEW_LINE {0}: {1}" -f ($i+1), $lines[$i])
  }
}
[IO.File]::WriteAllLines($tp, $lines, $utf8)
Write-Host 'PIPELINE_TEST_UPDATED'

Write-Host '===== test-connect-pipeline ====='
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-connect-pipeline.ps1
Write-Host ("EXIT_pipeline=$LASTEXITCODE")
