#Requires -Version 5.1
# Clear-ConnectTestTemp.ps1 - best-effort cleanup of connect test leftovers under %TEMP%
$ErrorActionPreference = 'Continue'

function Test-ProtectedTempName {
    param([string]$Name)

    if ($Name -eq 'claude-connect-setup.log') { return $true }
    if ($Name -like 'claude-connect-deferred-setup-*.json') { return $true }
    if ($Name -like 'claude-connect-run-id.*') { return $true }
    return $false
}

function Add-Removed {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if ($List -notcontains $Path) {
        $List.Add($Path) | Out-Null
    }
}

function Add-Skipped {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Message
    )
    if ($List -notcontains $Message) {
        $List.Add($Message) | Out-Null
    }
}

function Remove-TempPathBestEffort {
    param(
        [string]$Path,
        [switch]$Recurse,
        [System.Collections.Generic.List[string]]$Removed,
        [System.Collections.Generic.List[string]]$Skipped
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $leaf = Split-Path -Leaf $Path
    if (Test-ProtectedTempName -Name $leaf) {
        Add-Skipped -List $Skipped -Message "$Path (protected product artifact)"
        return
    }

    try {
        if ($Recurse) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        else {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        Add-Removed -List $Removed -Path $Path
    }
    catch {
        Add-Skipped -List $Skipped -Message "$Path ($($_.Exception.Message))"
    }
}

function Remove-EmptyClientUpdateDirs {
    param(
        [string]$TempRoot,
        [System.Collections.Generic.List[string]]$Removed,
        [System.Collections.Generic.List[string]]$Skipped
    )

    Get-ChildItem -LiteralPath $TempRoot -Directory -Filter 'claude-client-update-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dir = $_
            $hasChildren = $false
            try {
                $hasChildren = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop).Count -gt 0
            }
            catch {
                Add-Skipped -List $Skipped -Message "$($dir.FullName) (locked or in use)"
                return
            }

            if ($hasChildren) {
                Add-Skipped -List $Skipped -Message "$($dir.FullName) (not empty; product staging)"
                return
            }

            Remove-TempPathBestEffort -Path $dir.FullName -Removed $Removed -Skipped $Skipped
        }
}

$tempRoot = $env:TEMP
$removed = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

if ([string]::IsNullOrWhiteSpace($tempRoot)) {
    Write-Host 'Clear-ConnectTestTemp: TEMP is not set; nothing to do.'
    exit 0
}

if (-not (Test-Path -LiteralPath $tempRoot)) {
    Write-Host "Clear-ConnectTestTemp: TEMP path missing: $tempRoot"
    exit 0
}

Write-Host "Clear-ConnectTestTemp: scanning $tempRoot"

# All agent/debug leftovers named cc-* (files + dirs). Product files never use this prefix.
Get-ChildItem -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'cc-*' } |
    ForEach-Object {
        if ($_.PSIsContainer) {
            Remove-TempPathBestEffort -Path $_.FullName -Recurse -Removed $removed -Skipped $skipped
        }
        else {
            Remove-TempPathBestEffort -Path $_.FullName -Removed $removed -Skipped $skipped
        }
    }

$specificFiles = @(
    'claude-connect-kill-self.marker'
    'claude-connect-live-reuse.exe'
)

foreach ($name in $specificFiles) {
    Remove-TempPathBestEffort -Path (Join-Path $tempRoot $name) -Removed $removed -Skipped $skipped
}

foreach ($pattern in @('ccb-so-sepidz', 'cc-scope-test')) {
    Get-ChildItem -LiteralPath $tempRoot -Directory -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            Remove-TempPathBestEffort -Path $_.FullName -Recurse -Removed $removed -Skipped $skipped
        }
}

Remove-EmptyClientUpdateDirs -TempRoot $tempRoot -Removed $removed -Skipped $skipped

Write-Host ''
if ($removed.Count -eq 0) {
    Write-Host 'Removed: (none)'
}
else {
    Write-Host 'Removed:'
    foreach ($item in $removed) {
        Write-Host "  $item"
    }
}

if ($skipped.Count -gt 0) {
    Write-Host ''
    Write-Host 'Skipped:'
    foreach ($item in $skipped) {
        Write-Host "  $item"
    }
}

Write-Host ''
Write-Host 'Clear-ConnectTestTemp: done (exit 0).'
exit 0
