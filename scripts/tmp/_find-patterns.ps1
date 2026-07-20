$ErrorActionPreference = 'Continue'
$paths = @(
  'publish\publish.ps1',
  'publish\deploy-client-bundles.ps1'
)
foreach ($p in $paths) {
  if (-not (Test-Path $p)) { Write-Host "MISSING $p"; continue }
  Write-Host "==== $p ===="
  Select-String -Path $p -Pattern 'IdentityAgent|manifest|UTF8Encoding|BOM|checksums|sha256|Set-Content|WriteAllText' |
    ForEach-Object { '{0}:{1}:{2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() }
}
Write-Host '==== IdentityAgent anywhere ===='
Get-ChildItem -Recurse -Include *.ps1,*.sh -Path publish,scripts\client,scripts\server |
  Select-String -Pattern 'IdentityAgent' -ErrorAction SilentlyContinue |
  ForEach-Object { '{0}:{1}:{2}' -f $_.Path.Replace((Get-Location).Path + '\',''), $_.LineNumber, $_.Line.Trim() }
