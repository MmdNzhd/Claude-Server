$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'client\windows\connect.bat'
$path = Resolve-Path $path
$lines = [System.IO.File]::ReadAllLines($path)
$out = New-Object System.Collections.Generic.List[string]
foreach ($line in $lines) {
    if ($line -eq '            start "" /D "%HERE%" "%~f0"') {
        $out.Add('            start "" /D "%HERE%" "%~f0" %*')
    } elseif ($line -eq '            exit /b 0') {
        $out.Add('            exit 0')
    } else {
        $out.Add($line)
    }
}
[System.IO.File]::WriteAllLines($path, $out)
Write-Host "Patched $path"
