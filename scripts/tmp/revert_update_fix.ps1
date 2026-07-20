$ErrorActionPreference='Stop'
$root = 'D:\Smart\Claude-Code-Server'
$upd = Join-Path $root 'scripts\client\windows\connect-update.ps1'
$t = [IO.File]::ReadAllText($upd)

# Restore 20s timeout
if ($t -notmatch 'TimeoutMs 8000 -RequireStdout') { throw 'expected 8000 timeout not found' }
$t = $t.Replace(
  '$r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 8000 -RequireStdout',
  '$r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout'
)

# Add 3 attempts inside Invoke-SshCat (timeout each try, then fail)
$oldCat = @'
function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    Write-UpdateFileLog ("SSH_STAGE cat begin target=$Target path=$RemotePath")
    $args = $script:SshCommonOpts + @($Target, "cat '$RemotePath'")
    $r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout
    if (-not $r.Ok) {
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
        Write-UpdateFileLog ("SSH_STAGE cat FAIL target=$Target exit=$($r.ExitCode) err=$err") 'WARN'
        return $null
    }
    Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length)")
    return $r.Out
}
'@

$newCat = @'
function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    Write-UpdateFileLog ("SSH_STAGE cat begin target=$Target path=$RemotePath")
    $args = $script:SshCommonOpts + @($Target, "cat '$RemotePath'")
    # Up to 3 tries (timeout/retry). Caller may still fall back to another account.
    $r = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout
        if ($r.Ok) {
            if ($attempt -gt 1) {
                Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length) attempt=$attempt")
            } else {
                Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length)")
            }
            return $r.Out
        }
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 200) { $err = $err.Substring(0, 200) }
        Write-UpdateFileLog ("SSH_STAGE cat FAIL target=$Target attempt=$attempt/3 exit=$($r.ExitCode) err=$err") 'WARN'
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }
    return $null
}
'@

if ($t -notmatch 'function Invoke-SshCat') { throw 'Invoke-SshCat missing' }
# replace function body by regex from function to next function
$pattern = '(?s)function Invoke-SshCat \{.*?\r?\n\}\r?\n\r?\nfunction Invoke-BundleDownload'
if ($t -notmatch $pattern) {
  # try without double newline
  $pattern = '(?s)function Invoke-SshCat \{.*?\n\}\n\nfunction Invoke-BundleDownload'
}
$m = [regex]::Match($t, '(?s)function Invoke-SshCat \{.*?^\}\r?\n\r?\nfunction Invoke-BundleDownload', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $m.Success) {
  # show nearby
  $idx = $t.IndexOf('function Invoke-SshCat')
  throw ("cat replace pattern fail near: " + $t.Substring($idx, [Math]::Min(400, $t.Length-$idx)))
}
$t = $t.Substring(0, $m.Index) + $newCat.TrimEnd() + "`r`n`r`nfunction Invoke-BundleDownload" + $t.Substring($m.Index + $m.Length - 'function Invoke-BundleDownload'.Length)

[IO.File]::WriteAllText($upd, $t)

# Fix version drift: bump to .19 consistently
$ver = '20260719.19'
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), $ver + "`n")
$mac = Join-Path $root 'scripts\client\mac\connect-version.txt'
if (Test-Path $mac) { [IO.File]::WriteAllText($mac, $ver + "`n") }
$cp = Join-Path $root 'scripts\client\windows\connect.ps1'
$cpt = [IO.File]::ReadAllText($cp)
$cpt2 = [regex]::Replace($cpt, "\`$script:ConnectVersion = '20260719\.\d+'", "`$script:ConnectVersion = '$ver'", 1)
if ($cpt2 -eq $cpt) { throw 'ConnectVersion replace failed' }
[IO.File]::WriteAllText($cp, $cpt2)

# verify
$v1 = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
$v2 = ([regex]::Match([IO.File]::ReadAllText($cp), "ConnectVersion = '([^']+)'")).Groups[1].Value
$has20 = Select-String -Path $upd -Pattern 'TimeoutMs 20000 -RequireStdout' -Quiet
$has3 = Select-String -Path $upd -Pattern 'attempt -le 3' -Quiet
$has8 = Select-String -Path $upd -Pattern 'TimeoutMs 8000 -RequireStdout' -Quiet
Write-Host "ver_txt=$v1 connect.ps1=$v2 timeout20=$has20 retry3=$has3 still8=$has8"
if ($v1 -ne $ver -or $v2 -ne $ver) { throw 'version mismatch' }
if (-not $has20 -or -not $has3 -or $has8) { throw 'update fix incomplete' }
Write-Host 'OK'
