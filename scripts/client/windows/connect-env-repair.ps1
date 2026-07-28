# connect-env-repair.ps1 - fix broken DOS 8.3 USERPROFILE/TEMP (dot usernames).
# Dot-source early from connect-update.ps1 / connect.ps1 / connect-preflight.ps1.
# Or: powershell -File connect-env-repair.ps1 -EmitBatEnv  (KEY=VALUE lines for connect.bat)
# Symptom: "An object at the specified path C:\Users\XXXX~1.YYY does not exist."

param(
    [switch]$EmitBatEnv
)

function Repair-ConnectWindowsProfileTempEnv {
    [CmdletBinding()]
    param()

    $longProfile = $null
    try {
        $fp = [Environment]::GetFolderPath('UserProfile')
        if ($fp -and ($fp -notmatch '~') -and (Test-Path -LiteralPath $fp)) {
            $longProfile = $fp
        }
    } catch {}

    if (-not $longProfile) {
        $u = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
        if ($u -and ($u -notmatch '~')) {
            foreach ($root in @('C:\Users', 'D:\Users')) {
                $guess = Join-Path $root $u
                if (Test-Path -LiteralPath $guess) {
                    $longProfile = $guess
                    break
                }
            }
        }
    }

    if ($longProfile -and ($longProfile -notmatch '~') -and (Test-Path -LiteralPath $longProfile)) {
        if (-not $env:USERPROFILE -or ($env:USERPROFILE -match '~') -or -not (Test-Path -LiteralPath $env:USERPROFILE)) {
            $env:USERPROFILE = $longProfile
        }
        $longLocal = Join-Path $longProfile 'AppData\Local'
        if ((Test-Path -LiteralPath $longLocal) -and (
                -not $env:LOCALAPPDATA -or ($env:LOCALAPPDATA -match '~') -or -not (Test-Path -LiteralPath $env:LOCALAPPDATA))) {
            $env:LOCALAPPDATA = $longLocal
        }
    }

    $tempCandidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
        [void]$tempCandidates.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
    }
    if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
        [void]$tempCandidates.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
    }
    try {
        $p = [IO.Path]::GetTempPath()
        if ($p -and ($p -notmatch '~')) { [void]$tempCandidates.Add($p) }
    } catch {}
    if ($env:TEMP -and ($env:TEMP -notmatch '~')) { [void]$tempCandidates.Add($env:TEMP) }
    if ($env:TMP -and ($env:TMP -notmatch '~')) { [void]$tempCandidates.Add($env:TMP) }
    if ($env:SystemRoot) {
        [void]$tempCandidates.Add((Join-Path $env:SystemRoot 'Temp'))
    }

    foreach ($cand in $tempCandidates) {
        if (-not $cand) { continue }
        if ($cand -match '~') { continue }
        try {
            if (-not (Test-Path -LiteralPath $cand)) {
                New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            }
            $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
            if ($full -and ($full -notmatch '~')) {
                $env:TEMP = $full
                $env:TMP = $full
                return
            }
        } catch { continue }
    }
}

Repair-ConnectWindowsProfileTempEnv

if ($EmitBatEnv) {
    if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
        Write-Output ('USERPROFILE=' + $env:USERPROFILE)
    }
    if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
        Write-Output ('LOCALAPPDATA=' + $env:LOCALAPPDATA)
    }
    if ($env:TEMP -and ($env:TEMP -notmatch '~')) {
        Write-Output ('TEMP=' + $env:TEMP)
        Write-Output ('TMP=' + $env:TEMP)
    }
}
