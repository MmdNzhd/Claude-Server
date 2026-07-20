$ErrorActionPreference = 'Stop'
$path = 'D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$raw = [System.IO.File]::ReadAllText($path)
$rawN = $raw -replace "`r`n", "`n"

$old = @'
function Ensure-EditorOnPath {
    param([string]$EditorCmd)
    $leaf = if ($EditorCmd -eq 'cursor') { 'cursor.cmd' } else { 'code.cmd' }
    $relBin = if ($EditorCmd -eq 'cursor') { 'resources\app\bin' } else { 'bin' }
    $folder = if ($EditorCmd -eq 'cursor') { 'cursor' } else { 'Microsoft VS Code' }
    foreach ($u in @($script:LaptopUser, $env:USERNAME) | Where-Object { $_ }) {
        $root = [System.IO.Path]::Combine("C:\Users\$u\AppData\Local\Programs", $folder)
        $binDir = [System.IO.Path]::Combine($root, $relBin)
        $cli = [System.IO.Path]::Combine($binDir, $leaf)
        if (Test-Path $cli) {
            if ($env:Path -notlike "*$([regex]::Escape($binDir))*") {
                $env:Path = "$binDir;$env:Path"
            }
            return $cli
        }
    }
    return $null
}
'@

$new = @'
function Ensure-EditorOnPath {
    param([string]$EditorCmd)
    $leaf = if ($EditorCmd -eq 'cursor') { 'cursor.cmd' } else { 'code.cmd' }
    $exeLeaf = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $relBin = if ($EditorCmd -eq 'cursor') { 'resources\app\bin' } else { 'bin' }
    $folder = if ($EditorCmd -eq 'cursor') { 'cursor' } else { 'Microsoft VS Code' }

    function ConvertTo-EditorCliFromRoot {
        param([string]$Root)
        if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
        $binDir = [System.IO.Path]::Combine($Root, $relBin)
        $cli = [System.IO.Path]::Combine($binDir, $leaf)
        if (Test-Path -LiteralPath $cli) { return $cli }
        $exe = [System.IO.Path]::Combine($Root, $exeLeaf)
        if (Test-Path -LiteralPath $exe) { return $exe }
        return $null
    }

    function Add-EditorBinToPath {
        param([string]$CliPath)
        if (-not $CliPath) { return $null }
        $binDir = Split-Path -Parent $CliPath
        # If we resolved Cursor.exe at install root, prefer resources\app\bin when present
        if ($CliPath -match '\\Cursor\.exe$' -or $CliPath -match '\\Code\.exe$') {
            $maybeBin = [System.IO.Path]::Combine((Split-Path -Parent $CliPath), $relBin)
            $maybeCli = [System.IO.Path]::Combine($maybeBin, $leaf)
            if (Test-Path -LiteralPath $maybeCli) {
                $CliPath = $maybeCli
                $binDir = $maybeBin
            }
        }
        if ($binDir -and ($env:Path -notlike "*$([regex]::Escape($binDir))*")) {
            $env:Path = "$binDir;$env:Path"
        }
        return $CliPath
    }

    # 1) Preferred accounts first (LaptopUser / current), then every local profile.
    #    Fixes Admin connect when Cursor is installed under another Windows user.
    $userNames = New-Object System.Collections.Generic.List[string]
    foreach ($u in @($script:LaptopUser, $env:USERNAME)) {
        if ($u -and -not $userNames.Contains($u)) { [void]$userNames.Add($u) }
    }
    $usersRoot = 'C:\Users'
    if (Test-Path -LiteralPath $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') } |
            ForEach-Object {
                if (-not $userNames.Contains($_.Name)) { [void]$userNames.Add($_.Name) }
            }
    }

    foreach ($u in $userNames) {
        $root = [System.IO.Path]::Combine("C:\Users\$u\AppData\Local\Programs", $folder)
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 2) Current LOCALAPPDATA + machine-wide Program Files
    $candidateRoots = @(
        $(if ($env:LOCALAPPDATA) { [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', $folder) } else { $null }),
        $(if ($env:ProgramFiles) { [System.IO.Path]::Combine($env:ProgramFiles, $folder) } else { $null }),
        $(if (${env:ProgramFiles(x86)}) { [System.IO.Path]::Combine(${env:ProgramFiles(x86)}, $folder) } else { $null })
    ) | Where-Object { $_ }
    foreach ($root in $candidateRoots) {
        $hit = ConvertTo-EditorCliFromRoot -Root $root
        if ($hit) { return (Add-EditorBinToPath -CliPath $hit) }
    }

    # 3) Already on PATH (Get-Command)
    $cmd = Get-Command $EditorCmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
        return (Add-EditorBinToPath -CliPath $cmd.Source)
    }

    return $null
}
'@

$oldN = $old -replace "`r`n", "`n"
$newN = $new -replace "`r`n", "`n"
if (-not $rawN.Contains($oldN)) { throw 'Ensure-EditorOnPath block not found (already patched?)' }
$rawN = $rawN.Replace($oldN, $newN)

# Keep UTF8 BOM like other client scripts
$enc = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($path, ($rawN -replace "`n", "`r`n"), $enc)

$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { throw ("parse errors: " + (($errs | ForEach-Object Message) -join '; ')) }
Write-Output 'OK editor-launch Ensure-EditorOnPath'

# Improve diagnostic message
$diag = 'D:\Smart\Claude-Code-Server\scripts\client\connect-diagnostic.ps1'
$d = [System.IO.File]::ReadAllText($diag) -replace "`r`n", "`n"
$oldD = @'
            Code = 'CURSOR_NOT_FOUND'; Severity = 'ERROR'; Summary = 'Cursor not installed.'
            Cause = 'Cursor.exe missing from PATH.'
            Fix = 'Install Cursor or switch to VS Code in config.'
'@
$newD = @'
            Code = 'CURSOR_NOT_FOUND'; Severity = 'ERROR'; Summary = 'Cursor not found for this Windows user.'
            Cause = 'cursor.cmd / Cursor.exe not found under any profile (common when connect runs as Admin but Cursor is installed for another user).'
            Fix = 'Run connect as the Windows user who owns Cursor, or reinstall Cursor for this account. Or switch to VS Code.'
'@
if ($d.Contains(($oldD -replace "`r`n","`n"))) {
    $d = $d.Replace(($oldD -replace "`r`n","`n"), ($newD -replace "`r`n","`n"))
    [System.IO.File]::WriteAllText($diag, ($d -replace "`n","`r`n"), (New-Object System.Text.UTF8Encoding $false))
    Write-Output 'OK connect-diagnostic message'
} else {
    Write-Output 'WARN diagnostic message already changed or mismatch'
}
