param([string[]]$Paths, [int]$ExpectedSize = 303104)
foreach ($Path in $Paths) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Output "PATH|$Path|MISSING|0"; continue }
    $fi = Get-Item -LiteralPath $Path
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $mz = if ($bytes.Length -ge 2) { [char]$bytes[0] + [char]$bytes[1] } else { '??' }
    $peOk = $false
    if ($bytes.Length -ge 64 -and $mz -eq 'MZ') {
        $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
        if ($peOff -lt $bytes.Length - 4) {
            $b0 = $bytes[$peOff]; $b1 = $bytes[$peOff+1]; $b2 = $bytes[$peOff+2]; $b3 = $bytes[$peOff+3]
            if ($b0 -eq 0x50 -and $b1 -eq 0x45 -and $b2 -eq 0 -and $b3 -eq 0) { $peOk = $true }
        }
    }
    $st = if ($peOk -and $fi.Length -eq $ExpectedSize) { 'GOOD' } elseif ($peOk) { 'PE_OK_SIZE_MISMATCH' } else { 'BAD_PE' }
    Write-Output "PATH|$Path|$st|$($fi.Length)"
}
