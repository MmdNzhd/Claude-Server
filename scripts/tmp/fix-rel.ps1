$ErrorActionPreference = 'Stop'
$gm = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }
$old = '    } elseif ($uidStr -and $Port) {
        Write-GitModeLog "ENSURE_TUNNEL skip_acquire port=$Port reason=already_set" ''DEBUG''
    }

    Release-StaleTunnelPort
    if ($SshCfgPath) { Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias }'
# use exact quotes from file
$idx = $g.IndexOf('ENSURE_TUNNEL skip_acquire port=$Port reason=already_set')
if ($idx -lt 0) { throw 'skip_acquire missing' }
$rel = $g.IndexOf('Release-StaleTunnelPort', $idx)
if ($rel -lt 0) { throw 'Release after skip missing' }
# only replace the one right after skip_acquire (within 200 chars)
if ($rel - $idx -gt 250) { throw "too far: $($rel-$idx)" }
$lineStart = $g.LastIndexOf("`n", $rel) + 1
$lineEnd = $g.IndexOf("`n", $rel)
$oldLine = $g.Substring($lineStart, $lineEnd - $lineStart)
Write-Host "OLD_LINE=$oldLine"
$replacement = @'
    $needStaleClear = $false
    if ($Port) {
        $haveLocal = (@(Get-LocalTunnelSshPids -TargetPort $Port).Count -gt 0)
        if (-not $haveLocal) {
            $tcpOpen2 = $false
            try { $tcpOpen2 = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen2 = $false }
            if ($tcpOpen2) { $needStaleClear = $true }
        }
    }
    if ($needStaleClear) { Release-StaleTunnelPort }
    else { Write-GitModeLog "ENSURE_TUNNEL skip_release_stale port=$Port" 'DEBUG' }
'@
if ($nl -eq "`r`n") { $replacement = ($replacement -replace "(?<!\r)`n", "`r`n").TrimEnd() + $nl }
else { $replacement = $replacement.TrimEnd() + $nl }
$g = $g.Remove($lineStart, $lineEnd - $lineStart + 1).Insert($lineStart, $replacement)
[IO.File]::WriteAllText($gm, $g)
$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm,[ref]$null,[ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse' }
if (-not [IO.File]::ReadAllText($gm).Contains('skip_release_stale')) { throw 'missing' }
Write-Host 'OK'

# publish + sync
$root = 'D:\Smart\Claude-Code-Server'
# ensure version 14
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.14'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.14')

& (Join-Path $root 'publish\publish.ps1') -SmartOnly -SkipVersionBump | Out-Host
$pub = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260721\windows'
foreach ($t in @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows')
)) {
  foreach ($f in @('connect.bat','connect-boot.ps1','connect-version.txt','connect-update.ps1','connect.ps1','connect-ui.ps1','git-mode.ps1','editor-launch.ps1','cursor-auth-laptop.ps1','connect-diagnostic.ps1')) {
    $src = Join-Path $pub $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $t $f) -Force }
  }
  $raw = Get-Content (Join-Path $t 'git-mode.ps1') -Raw
  Write-Host ("SYNC {0} ver={1} emptyfix={2} adopt={3} sticky={4}" -f $t,
    (Get-Content (Join-Path $t 'connect-version.txt') -Raw).Trim(),
    [int]($raw -match 'no_probe_ports'),
    [int]($raw -match 'adopt_local_forward'),
    [int]($raw -match 'claim_sticky'))
}
