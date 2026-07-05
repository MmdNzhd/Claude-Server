# bump-connect-version.ps1 — bump yyyyMMdd.N on each publish (dot-source from publish.ps1)
Set-StrictMode -Version Latest

function Get-RepoConnectVersion {
    param([string]$ProjectRoot)
    $ps1 = Join-Path $ProjectRoot 'scripts\client\windows\connect.ps1'
    if (-not (Test-Path $ps1)) { return '' }
    $raw = Get-Content $ps1 -Raw
    if ($raw -match "ConnectVersion = '([^']+)'") { return $Matches[1] }
    return ''
}

function Get-NextConnectVersion {
    param(
        [string]$Current,
        [datetime]$Now = (Get-Date)
    )
    $today = $Now.ToString('yyyyMMdd')
    if ($Current -match '^(\d{8})\.(\d+)$') {
        $curDate = $Matches[1]
        $build = [int]$Matches[2]
        if ($curDate -eq $today) { return "${today}.$($build + 1)" }
    }
    return "${today}.1"
}

function Set-ConnectVersionInRepo {
    param(
        [string]$ProjectRoot,
        [string]$Version
    )
    $replacements = @(
        @{
            Path    = Join-Path $ProjectRoot 'scripts\client\windows\connect.ps1'
            Pattern = "ConnectVersion = '[^']+'"
            Replace = "ConnectVersion = '$Version'"
        },
        @{
            Path    = Join-Path $ProjectRoot 'scripts\client\mac\connect.sh'
            Pattern = "CONNECT_VERSION='[^']+'"
            Replace = "CONNECT_VERSION='$Version'"
        },
        @{
            Path    = Join-Path $ProjectRoot 'publish\README.txt'
            Pattern = 'v\d{8}\.\d+'
            Replace = "v$Version"
        },
        @{
            Path    = Join-Path $ProjectRoot 'scripts\client\users\designer\README.md'
            Pattern = 'v\d{8}\.\d+'
            Replace = "v$Version"
        },
        @{
            Path    = Join-Path $ProjectRoot 'docs\client-connect.md'
            Pattern = '\*\*`(\d{8}\.\d+)`\*\*'
            Replace = "**``$Version``**"
        },
        @{
            Path    = Join-Path $ProjectRoot 'docs\client-connect.md'
            Pattern = 'v\d{8}\.\d+'
            Replace = "v$Version"
        },
        @{
            Path    = Join-Path $ProjectRoot 'scripts\server\commands\deploy-mount-fix.sh'
            Pattern = 'connect\.bat \(v\d{8}\.\d+\+\)'
            Replace = "connect.bat (v$Version+)"
        }
    )

    foreach ($item in $replacements) {
        if (-not (Test-Path $item.Path)) { continue }
        $raw = Get-Content $item.Path -Raw
        $new = [regex]::Replace($raw, $item.Pattern, $item.Replace)
        if ($new -ne $raw) {
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($item.Path, $new, $utf8NoBom)
        }
    }

    $verFile = Join-Path $ProjectRoot 'scripts\client\windows\connect-version.txt'
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($verFile, $Version, $utf8NoBom)
}

function Invoke-BumpConnectVersion {
    param([string]$ProjectRoot)
    $current = Get-RepoConnectVersion -ProjectRoot $ProjectRoot
    $next = Get-NextConnectVersion -Current $current
    Set-ConnectVersionInRepo -ProjectRoot $ProjectRoot -Version $next
    return $next
}
