$ErrorActionPreference = 'Stop'
$path = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
$raw = [IO.File]::ReadAllText($path)

$start = $raw.IndexOf('function Get-ServerEndpoint')
if ($start -lt 0) { throw 'Get-ServerEndpoint not found' }
$end = $raw.IndexOf('function Invoke-SshTimed', $start)
if ($end -lt 0) { throw 'Invoke-SshTimed not found after Get-ServerEndpoint' }

$new = @'
function Get-RemoteUserFromConf {
    # Prefer the laptop user's own server account (farzadb, hosseinb, ...).
    # Bundle is world-readable; sepidz@ only works for machines with the sepidz deploy key.
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'))
    try {
        $lu = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        if ($lu -match '\\(.+)$') {
            $u = $Matches[1]
            $candidates.Add("C:\Users\$u\.config\claude-connect\connect.conf")
        }
    } catch {}
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        foreach ($line in Get-Content -LiteralPath $c -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*REMOTE_USER=(.+)$') {
                $u = $Matches[1].Trim().Trim('"').Trim("'")
                if ($u -and ($u -notmatch '[@/\\]')) { return $u }
            }
        }
    }
    return ''
}

function Get-ServerEndpoint {
    # Always user@IP from this package. NEVER Host alias "claude-server"
    # (often points at Smart 210.240 -> Sepidz clients pull frozen .22).
    $ip = Get-LocalServerIp
    if ($env:CLAUDE_UPDATE_SSH_TARGET) {
        $t = $env:CLAUDE_UPDATE_SSH_TARGET.Trim()
        return @{ Target = $t; Display = $t }
    }
    if ($ip) {
        $user = Get-RemoteUserFromConf
        if (-not $user) {
            $user = if ($ip -eq '192.168.250.70') { 'sepidz' } elseif ($ip -eq '192.168.210.240') { 'smart' } else { 'smart' }
        }
        $t = "{0}@{1}" -f $user, $ip
        return @{ Target = $t; Display = $t }
    }
    return @{ Target = 'smart@192.168.210.240'; Display = 'smart@192.168.210.240' }
}

'@

$raw2 = $raw.Substring(0, $start) + $new + $raw.Substring($end)
[IO.File]::WriteAllText($path, $raw2)
Write-Host 'patched OK'
# sanity
$check = [IO.File]::ReadAllText($path)
if ($check -notmatch 'Get-RemoteUserFromConf') { throw 'patch missing helper' }
if ($check -notmatch 'Prefer the laptop') { throw 'patch content missing' }
Write-Host 'sanity OK'
