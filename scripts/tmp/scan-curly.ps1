$ErrorActionPreference = 'Stop'
$codes = @(0x201C,0x201D,0x2018,0x2019,0x2013,0x2014)
$files = @(
  'scripts\client\windows\connect.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\editor-launch.ps1',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\windows\connect.bat',
  'scripts\client\tests\test-connect-pipeline.ps1',
  'scripts\client\tests\_scan-unicode.ps1',
  'publish\Get-DeployCredentials.ps1',
  'publish\deploy-client-bundles.ps1',
  'publish\publish.ps1',
  'publish\finish-sepidz-deploy.ps1',
  'publish\finish-smart-deploy.ps1',
  'publish\deploy-smart-bundle.ps1',
  'scripts\client\users\designer\connect.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\windows\connect-diagnostic.ps1'
)
foreach ($f in $files) {
  if (-not (Test-Path $f)) { Write-Host "MISSING $f"; continue }
  $bytes = [IO.File]::ReadAllBytes((Resolve-Path $f))
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  $hits = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $text.Length; $i++) {
    $c = [int][char]$text[$i]
    if ($codes -contains $c) {
      $line = ($text.Substring(0,$i) -split "`n").Count
      $hits.Add(("U+{0:X4}@L{1}" -f $c, $line)) | Out-Null
    }
  }
  if ($bom -or $hits.Count -gt 0) {
    Write-Host ("BAD {0} BOM={1} count={2} {3}" -f $f, $bom, $hits.Count, (($hits | Select-Object -First 30) -join '; '))
  } else {
    Write-Host ("OK {0} bytes={1}" -f $f, $bytes.Length)
  }
}
