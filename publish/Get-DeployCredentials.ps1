# Get-DeployCredentials.ps1 - load local deploy passwords (never committed)
# Real secrets live ONLY in publish/*-deploy.local.ps1 (gitignored) or env vars.
# See publish/sepidz-deploy.local.ps1.example / publish/smart-deploy.local.ps1.example.
Set-StrictMode -Version Latest

function Read-LocalDeployValue {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Name,
        [switch]$RequireFile
    )
    $localFile = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path -LiteralPath $localFile)) {
        if ($RequireFile) {
            throw @"
Missing deploy credentials file: publish/$FileName
Copy publish/$FileName.example to publish/$FileName and set real values.
No hardcoded password fallback is allowed.
"@
        }
        return $null
    }
    $content = Get-Content -LiteralPath $localFile -Raw
    if ($content -match ("${Name}\s*=\s*'([^']*)'")) { return $Matches[1] }
    if ($content -match ("${Name}\s*=\s*`"([^`"]*)`"")) { return $Matches[1] }
    return $null
}

function Read-SepidzLocalValue {
    param([string]$Name, [switch]$RequireFile)
    return Read-LocalDeployValue -FileName 'sepidz-deploy.local.ps1' -Name $Name -RequireFile:$RequireFile
}

function Get-SepidzSshUser {
    if ($env:SEPIDZ_SSH_USER) { return $env:SEPIDZ_SSH_USER.Trim() }
    $v = Read-SepidzLocalValue -Name 'SepidzSshUser'
    if ($v) { return $v }
    return 'sepidz'
}

function Get-SepidzServerTarget {
    $hostIp = if ($env:SEPIDZ_SERVER_IP) { $env:SEPIDZ_SERVER_IP.Trim() } else { '192.168.250.70' }
    return ('{0}@{1}' -f (Get-SepidzSshUser), $hostIp)
}

function Get-SepidzSudoPassword {
    if ($env:SEPIDZ_SUDO_PASSWORD) {
        $t = $env:SEPIDZ_SUDO_PASSWORD.Trim()
        if ($t) { return $t }
    }
    $localFile = Join-Path $PSScriptRoot 'sepidz-deploy.local.ps1'
    if (-not (Test-Path -LiteralPath $localFile)) {
        throw @"
Sepidz sudo password not found: publish/sepidz-deploy.local.ps1 is missing.
Copy publish/sepidz-deploy.local.ps1.example to publish/sepidz-deploy.local.ps1 and set:
  `$SepidzSudoPassword = '...'
Or set env SEPIDZ_SUDO_PASSWORD. No hardcoded fallback is allowed.
"@
    }
    $v = Read-SepidzLocalValue -Name 'SepidzSudoPassword'
    if ($v -and $v.Trim()) { return $v.Trim() }
    throw @"
Sepidz sudo password not found in publish/sepidz-deploy.local.ps1.
Set `$SepidzSudoPassword = '...' (see sepidz-deploy.local.ps1.example)
or env SEPIDZ_SUDO_PASSWORD. No hardcoded fallback is allowed.
"@
}

function Get-SmartSudoPassword {
    if ($env:SMART_SUDO_PASSWORD) {
        $t = $env:SMART_SUDO_PASSWORD.Trim()
        if ($t) { return $t }
    }
    $localFile = Join-Path $PSScriptRoot 'smart-deploy.local.ps1'
    if (-not (Test-Path -LiteralPath $localFile)) {
        throw @"
Smart sudo password not found: publish/smart-deploy.local.ps1 is missing.
Copy publish/smart-deploy.local.ps1.example to publish/smart-deploy.local.ps1 and set:
  `$SmartSudoPassword = '...'
Or set env SMART_SUDO_PASSWORD. No hardcoded fallback is allowed.
"@
    }
    $v = Read-LocalDeployValue -FileName 'smart-deploy.local.ps1' -Name 'SmartSudoPassword'
    if ($v -and $v.Trim()) { return $v.Trim() }
    throw @"
Smart sudo password not found in publish/smart-deploy.local.ps1.
Set `$SmartSudoPassword = '...' (see smart-deploy.local.ps1.example)
or env SMART_SUDO_PASSWORD. No hardcoded fallback is allowed.
"@
}
