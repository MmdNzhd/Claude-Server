$ErrorActionPreference='Stop'
$path='D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1'
$lines=Get-Content $path

# Skip if already patched
if (($lines -join "`n") -match 'function Get-CursorAuthTempRoot') {
  Write-Output 'Already has Get-CursorAuthTempRoot'
} else {
  $helper = @(
    'function Get-CursorAuthTempRoot {',
    '    # Prefer a resolvable long path; broken 8.3 TEMP shorts (C:\Users\XXXX~1.YYY) can make Remove-Item',
    '    # throw a terminating error that connect.ps1 trap surfaces as Unexpected error on disconnect.',
    '    $candidates = New-Object System.Collections.Generic.List[string]',
    '    try { $p = [System.IO.Path]::GetTempPath(); if ($p) { [void]$candidates.Add($p) } } catch {}',
    '    if ($env:TEMP) { [void]$candidates.Add($env:TEMP) }',
    '    if ($env:TMP) { [void]$candidates.Add($env:TMP) }',
    '    if ($env:LOCALAPPDATA) { [void]$candidates.Add((Join-Path $env:LOCALAPPDATA ''Temp'')) }',
    '    [void]$candidates.Add((Join-Path $env:SystemRoot ''Temp''))',
    '    foreach ($cand in $candidates) {',
    '        if (-not $cand) { continue }',
    '        try {',
    '            if (-not (Test-Path -LiteralPath $cand)) {',
    '                New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null',
    '            }',
    '            $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName',
    '            if ($full) { return $full }',
    '        } catch { continue }',
    '    }',
    '    return [System.IO.Path]::GetTempPath()',
    '}',
    '',
    'function Remove-CursorAuthTempDir {',
    '    param([string]$Path)',
    '    if (-not $Path) { return }',
    '    try {',
    '        if (Test-Path -LiteralPath $Path) {',
    '            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop',
    '        }',
    '    } catch {',
    '        # never let temp cleanup abort connect disconnect',
    '    }',
    '}',
    ''
  )
  # insert before Get-RemoteCursorAuthFromGolden
  $insertAt = -1
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^function Get-RemoteCursorAuthFromGolden') { $insertAt = $i; break }
  }
  if ($insertAt -lt 0) { throw 'Get-RemoteCursorAuthFromGolden not found' }
  $new = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $insertAt; $i++) { [void]$new.Add($lines[$i]) }
  foreach ($h in $helper) { [void]$new.Add($h) }
  for ($i=$insertAt; $i -lt $lines.Count; $i++) { [void]$new.Add($lines[$i]) }
  $lines = $new.ToArray()
  Write-Output ("Inserted helpers before line " + ($insertAt+1))
}

# Replace TEMP join + finally remove
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\$tmp = Join-Path \$env:TEMP \("cursor-golden') {
    $lines[$i] = '    $tmp = Join-Path (Get-CursorAuthTempRoot) ("cursor-golden-{0}" -f [guid]::NewGuid().ToString(''n''))'
    Write-Output ("Patched tmp create at " + ($i+1))
  }
  if ($lines[$i] -match 'Remove-Item \$tmp -Recurse -Force -ErrorAction SilentlyContinue') {
    $lines[$i] = '        Remove-CursorAuthTempDir -Path $tmp'
    Write-Output ("Patched Remove-Item at " + ($i+1))
  }
}

Set-Content -Path $path -Value $lines -Encoding UTF8
Write-Output 'WRITE OK'
Select-String -Path $path -Pattern 'Get-CursorAuthTempRoot|Remove-CursorAuthTempDir|Join-Path \(Get-CursorAuthTempRoot\)|Join-Path \$env:TEMP \("cursor-golden|Remove-Item \$tmp -Recurse' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

# syntax check
$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
if ($errs) { Write-Output 'PARSE_ERRORS:'; $errs | ForEach-Object { $_.ToString() }; exit 1 } else { Write-Output 'PARSE_OK' }
