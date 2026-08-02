# bump-connect-version.ps1 - bump yyyyMMdd.N on each publish (dot-source from publish.ps1)
Set-StrictMode -Version Latest

$script:MaxBumpFileBytes = 2MB

function Get-RepoConnectVersion {
    param([string]$ProjectRoot)
    $ps1 = Join-Path $ProjectRoot 'scripts\client\windows\connect.ps1'
    if (-not (Test-Path $ps1)) { return '' }
    $raw = Get-Content $ps1 -Raw -Encoding UTF8
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

function Set-VersionInText {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replace
    )
    return [regex]::Replace($Text, $Pattern, $Replace)
}

function Write-BumpedFile {
    param(
        [string]$Path,
        [string]$NewText,
        [switch]$Utf8Bom
    )
    if ($Utf8Bom) {
        $enc = New-Object System.Text.UTF8Encoding $true
    } else {
        $enc = New-Object System.Text.UTF8Encoding $false
    }
    [System.IO.File]::WriteAllText($Path, $NewText, $enc)
}

function Invoke-BumpFileReplacement {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replace,
        [switch]$Utf8Bom
    )
    if (-not (Test-Path $Path)) { return }
    $info = Get-Item -LiteralPath $Path
    if ($info.Length -gt $script:MaxBumpFileBytes) {
        Write-Warning "skip bump (file too large: $($info.Length) bytes): $Path"
        return
    }
    $raw = [System.IO.File]::ReadAllText($Path)
    $new = Set-VersionInText -Text $raw -Pattern $Pattern -Replace $Replace
    if ($new -ne $raw) {
        Write-BumpedFile -Path $Path -NewText $new -Utf8Bom:$Utf8Bom
    }
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
            Utf8Bom = $false
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
            Path    = Join-Path $ProjectRoot 'publish\README-sepidz.txt'
            Pattern = 'v\d{8}\.\d+'
            Replace = "v$Version"
        },
        @{
            Path    = Join-Path $ProjectRoot 'scripts\client\users\designer\README.md'
            Pattern = 'v\d{8}\.\d+'
            Replace = "v$Version"
        },
        @{
            Path    = Join-Path $ProjectRoot 'CLAUDE.md'
            Pattern = "ConnectVersion = '\d{8}\.\d+'"
            Replace = "ConnectVersion = '$Version'"
        },
        @{
            Path    = Join-Path $ProjectRoot 'CLAUDE.md'
            Pattern = "CONNECT_VERSION='\d{8}\.\d+'"
            Replace = "CONNECT_VERSION='$Version'"
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
        $params = @{
            Path    = $item.Path
            Pattern = $item.Pattern
            Replace = $item.Replace
        }
        if ($item.ContainsKey('Utf8Bom') -and $item.Utf8Bom) {
            $params.Utf8Bom = $true
        }
        Invoke-BumpFileReplacement @params
    }

    $verFile = Join-Path $ProjectRoot 'scripts\client\windows\connect-version.txt'
    Write-BumpedFile -Path $verFile -NewText $Version
    $macVerFile = Join-Path $ProjectRoot 'scripts\client\mac\connect-version.txt'
    Write-BumpedFile -Path $macVerFile -NewText $Version

    # Lockstep with bundle: stale policy.latest breaks client checksum verify after deploy.
    $policyPath = Join-Path $ProjectRoot 'scripts\server\client-update-policy.json'
    if (Test-Path -LiteralPath $policyPath) {
        Invoke-BumpFileReplacement -Path $policyPath `
            -Pattern '("latest"\s*:\s*")[^"]*(")' `
            -Replace "`${1}$Version`${2}"
    }
}

function Set-ConnectBuildIdInRepo {
    param([string]$ProjectRoot)
    # Internal-only per-publish build tag - never shown in the console UI, never compared
    # for update/newer-than logic (unlike $Version above). Purely so a specific running
    # session's log can be tied back to the exact build that produced it. A fresh GUID
    # every publish; the user never sees it change.
    # Also stamped into git-mode.ps1 as GitModeBuildId so connect.bat / connect.ps1 can
    # detect split-generation installs (same version string, mixed file generations).
    $buildId = [guid]::NewGuid().ToString()
    Invoke-BumpFileReplacement -Path (Join-Path $ProjectRoot 'scripts\client\windows\connect.ps1') `
        -Pattern "ConnectBuildId = '[^']+'" -Replace "ConnectBuildId = '$buildId'" -Utf8Bom
    Invoke-BumpFileReplacement -Path (Join-Path $ProjectRoot 'scripts\client\git-mode.ps1') `
        -Pattern "GitModeBuildId = '[^']+'" -Replace "GitModeBuildId = '$buildId'"
    return $buildId
}

function Invoke-BumpConnectVersion {
    param([string]$ProjectRoot)
    $current = Get-RepoConnectVersion -ProjectRoot $ProjectRoot
    $next = Get-NextConnectVersion -Current $current
    Set-ConnectVersionInRepo -ProjectRoot $ProjectRoot -Version $next
    Set-ConnectBuildIdInRepo -ProjectRoot $ProjectRoot | Out-Null
    return $next
}
