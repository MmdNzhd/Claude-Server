$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
Write-Host "cwd=$repoRoot"

function Repair-File([string]$Full) {
    $bytes = [IO.File]::ReadAllBytes($Full)
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hadBom) { $bytes = $bytes[3..($bytes.Length-1)] }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $orig = $text
    foreach ($pair in @(
        @([char]0x201C, '"'),
        @([char]0x201D, '"'),
        @([char]0x2018, "'"),
        @([char]0x2019, "'"),
        @([char]0x2013, '-'),
        @([char]0x2014, '-')
    )) {
        $text = $text.Replace([string]$pair[0], [string]$pair[1])
    }
    if ($text -ne $orig -or $hadBom) {
        $enc = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($Full, $text, $enc)
        $rel = $Full.Substring($repoRoot.Length).TrimStart('\')
        Write-Host ("FIXED {0} bom={1} changed={2}" -f $rel, $hadBom, ($text -ne $orig))
        return $true
    }
    return $false
}

$fixed = 0
$roots = @('scripts\client', 'publish', '.gitignore')
# Fix .gitignore explicitly
$gi = Join-Path $repoRoot '.gitignore'
if (Test-Path $gi) { if (Repair-File $gi) { $fixed++ } }

Get-ChildItem -Path (Join-Path $repoRoot 'scripts\client'), (Join-Path $repoRoot 'publish') -Recurse -Include *.ps1,*.bat,*.sh,*.md,*.txt,*.example -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notmatch '\.local\.ps1$' } |
  ForEach-Object {
    if (Repair-File $_.FullName) { $fixed++ }
  }

Write-Host "FIXED_COUNT=$fixed"

# Verify no remaining in tracked-ish paths
$codes = @(0x201C,0x201D,0x2018,0x2019,0x2013,0x2014)
$bad = 0
Get-ChildItem -Path (Join-Path $repoRoot 'scripts\client'), (Join-Path $repoRoot 'publish') -Recurse -Include *.ps1,*.bat,*.sh -File |
  Where-Object { $_.Name -notmatch '\.local\.ps1$' } |
  ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $hits = 0
    foreach ($ch in $text.ToCharArray()) {
      if ($codes -contains [int]$ch) { $hits++ }
    }
    if ($bom -or $hits -gt 0) {
      $bad++
      $rel = $_.FullName.Substring($repoRoot.Length).TrimStart('\')
      Write-Host ("STILL_BAD {0} BOM={1} hits={2}" -f $rel, $bom, $hits)
    }
  }
Write-Host "STILL_BAD_COUNT=$bad"

# Exact pipeline assert
. (Join-Path $repoRoot 'scripts\client\tests\_paths.ps1')
$path = Get-ClientFile 'windows\connect.ps1'
$src = Get-Content $path -Raw
$ok = $src -notmatch '[\u201C\u201D\u2018\u2019]'
Write-Host ("PIPELINE_ASSERT_CURLY=$ok")
if (-not $ok) {
  for ($i=0; $i -lt $src.Length; $i++) {
    $c = [int][char]$src[$i]
    if ($c -in 0x201C,0x201D,0x2018,0x2019) {
      $line = ($src.Substring(0,$i) -split "`n").Count
      Write-Host ("HIT U+{0:X4} L{1}" -f $c, $line)
    }
  }
  exit 1
}
