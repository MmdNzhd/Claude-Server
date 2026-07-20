$ErrorActionPreference='Stop'
$path='D:\Smart\Claude-Code-Server\scripts\client\cursor-auth-laptop.ps1'
$c=Get-Content $path -Raw

# Add helper after the script header / near other helpers if not present
if ($c -notmatch 'function Get-CursorAuthTempRoot') {
  $helper = @'

function Get-CursorAuthTempRoot {
    # Prefer a resolvable long path; some Windows profiles have broken 8.3 TEMP shorts
    # (e.g. C:\Users\XXXX~1.YYY) that make Remove-Item throw into connect.ps1 trap.
    $candidates = @()
    try {
        $p = [System.IO.Path]::GetTempPath()
        if ($p) { $candidates += $p }
    } catch {}
    if ($env:TEMP) { $candidates += $env:TEMP }
    if ($env:TMP) { $candidates += $env:TMP }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Temp') }
    $candidates += (Join-Path $env:SystemRoot 'Temp')

    foreach ($cand in $candidates) {
        if (-not $cand) { continue }
        try {
            if (-not (Test-Path -LiteralPath $cand)) {
                New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            }
            $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
            if ($full) { return $full }
        } catch {
            continue
        }
    }
    return [System.IO.Path]::GetTempPath()
}

function Remove-CursorAuthTempDir {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    } catch {
        # never let temp cleanup abort connect disconnect
    }
}

'@
  # Insert after initial comment block / before first function - find first "function "
  $idx = $c.IndexOf("`nfunction ")
  if ($idx -lt 0) { throw 'no function anchor' }
  $c = $c.Insert($idx+1, $helper.TrimStart() + "`r`n`r`n")
}

$old = @'
function Get-RemoteCursorAuthFromGolden {
    param([Parameter(Mandatory)][string]$Alias)

    $tmp = Join-Path $env:TEMP ("cursor-golden-{0}" -f [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $ok = $true
        foreach ($pair in @(
            @{ Remote = '/etc/cursor-auth/golden/auth.json'; Local = 'auth.json' },
            @{ Remote = '/etc/cursor-auth/golden/state-keys.json'; Local = 'state-keys.json' },
            @{ Remote = '/etc/cursor-auth/golden/machine-id.txt'; Local = 'machine-id.txt' }
        )) {
            $dst = Join-Path $tmp $pair.Local
            scp -o BatchMode=yes -o ConnectTimeout=20 -q "${Alias}:$($pair.Remote)" $dst 2>$null
            if ($pair.Local -eq 'auth.json' -and $LASTEXITCODE -ne 0) { $ok = $false }
        }
        if (-not $ok) { return $null }
        return (Build-CursorAuthValuesFromGoldenDir -GoldenDir $tmp)
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
'@

$new = @'
function Get-RemoteCursorAuthFromGolden {
    param([Parameter(Mandatory)][string]$Alias)

    $tmp = Join-Path (Get-CursorAuthTempRoot) ("cursor-golden-{0}" -f [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $ok = $true
        foreach ($pair in @(
            @{ Remote = '/etc/cursor-auth/golden/auth.json'; Local = 'auth.json' },
            @{ Remote = '/etc/cursor-auth/golden/state-keys.json'; Local = 'state-keys.json' },
            @{ Remote = '/etc/cursor-auth/golden/machine-id.txt'; Local = 'machine-id.txt' }
        )) {
            $dst = Join-Path $tmp $pair.Local
            scp -o BatchMode=yes -o ConnectTimeout=20 -q "${Alias}:$($pair.Remote)" $dst 2>$null
            if ($pair.Local -eq 'auth.json' -and $LASTEXITCODE -ne 0) { $ok = $false }
        }
        if (-not $ok) { return $null }
        return (Build-CursorAuthValuesFromGoldenDir -GoldenDir $tmp)
    } finally {
        Remove-CursorAuthTempDir -Path $tmp
    }
}
'@

# Normalize line endings for match
$cN = $c -replace "`r`n","`n"
$oldN = $old -replace "`r`n","`n"
$newN = $new -replace "`r`n","`n"
if ($cN -notlike "*$($oldN.Substring(0,[Math]::Min(80,$oldN.Length)))*") {
  # try flexible replace of just the tmp creation + finally
  if ($cN -match '\$tmp = Join-Path \$env:TEMP \("cursor-golden') {
    Write-Output 'Using flexible patch'
  } else {
    throw 'old block not found'
  }
}

if ($cN.Contains($oldN)) {
  $cN2 = $cN.Replace($oldN, $newN)
} else {
  # flexible
  $cN2 = $cN.Replace(
    '$tmp = Join-Path $env:TEMP ("cursor-golden-{0}" -f [guid]::NewGuid().ToString(''n''))',
    '$tmp = Join-Path (Get-CursorAuthTempRoot) ("cursor-golden-{0}" -f [guid]::NewGuid().ToString(''n''))'
  )
  $cN2 = $cN2.Replace(
    'Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue',
    'Remove-CursorAuthTempDir -Path $tmp'
  )
}

if ($cN2 -eq $cN -and $c -match 'Get-CursorAuthTempRoot') {
  # maybe only helper added and replace already done
  Write-Output 'checking if already patched enough'
}

# Write as CRLF for Windows scripts
$out = ($cN2 -replace "`n","`r`n")
if ($out -notmatch 'Get-CursorAuthTempRoot') { throw 'helper missing after patch' }
if ($out -notmatch 'Remove-CursorAuthTempDir') { throw 'remover missing after patch' }
Set-Content -Path $path -Value $out -Encoding UTF8 -NoNewline
Write-Output 'PATCHED OK'
Select-String -Path $path -Pattern 'Get-CursorAuthTempRoot|Remove-CursorAuthTempDir|Join-Path \(Get-CursorAuthTempRoot\)|Remove-Item \$tmp -Recurse' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
