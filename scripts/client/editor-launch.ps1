# editor-launch.ps1 - shared VS Code/Cursor launch (dot-sourced by connect.ps1)
# Same pattern as mac/connect.sh:  cursor|code --folder-uri "vscode-remote://..."

function Get-CursorRemoteProfileSite {
    # Smart vs Sepidz must NOT share one laptop Cursor profile / golden merge.
    # Prefer explicit script scope set by connect.ps1; fall back to ServerIP / Alias.
    if ($script:CursorProfileSite) {
        $s = [string]$script:CursorProfileSite
        if ($s -match '(?i)^sepidz') { return 'Sepidz' }
        if ($s -match '(?i)^smart') { return 'Smart' }
    }
    $ip = ''
    if ($script:ServerIP) { $ip = [string]$script:ServerIP }
    if ($ip -eq '192.168.250.70') { return 'Sepidz' }
    if ($ip -eq '192.168.210.240') { return 'Smart' }
    $al = ''
    if ($script:SshAlias) { $al = [string]$script:SshAlias }
    if ($al -match '(?i)sepidz') { return 'Sepidz' }
    return 'Smart'
}

function Get-CursorRemoteProfileDir {
    # Isolated Cursor profile for server Remote-SSH. Smart and Sepidz use
    # separate dirs so each site's golden Cursor account cannot overwrite
    # the other. Personal Cursor (%APPDATA%\Cursor) is never touched.
    Ensure-CursorRemoteProfileMigrated
    $site = Get-CursorRemoteProfileSite
    if ($site -eq 'Sepidz') {
        return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Sepidz')
    }
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile-Smart')
}

function Get-CursorRemoteProfileDirSizeMB {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { return 0.0 }
    return [math]::Round(($sum / 1MB), 1)
}

function Stop-CursorRemoteProfileProcesses {
    # Soft-stop only server-profile Cursor (legacy or -Smart/-Sepidz). Never touches personal Cursor.
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $c = [string]$_.CommandLine
        $c -and ($c -match 'ClaudeServerCursorProfile')
    })
    foreach ($p in $procs) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($procs.Count -gt 0) { Start-Sleep -Seconds 2 }
    return $procs.Count
}

function Ensure-CursorRemoteProfileMigrated {
    # One-time: legacy %LOCALAPPDATA%\ClaudeServerCursorProfile -> ClaudeServerCursorProfile-Smart|Sepidz
    # so chat history / golden merge survive the site-split rename. Personal %APPDATA%\Cursor untouched.
    if ($script:CursorProfileMigrateChecked) { return }
    $script:CursorProfileMigrateChecked = $true
    if ($env:CLAUDE_CONNECT_SKIP_PROFILE_MIGRATE -eq '1') { return }
    if (-not $env:LOCALAPPDATA) { return }

    $site = Get-CursorRemoteProfileSite
    $legacy = Join-Path $env:LOCALAPPDATA 'ClaudeServerCursorProfile'
    $targetName = "ClaudeServerCursorProfile-$site"
    $target = Join-Path $env:LOCALAPPDATA $targetName
    $stamp = Join-Path $target '.claude-connect-profile-migrated'

    if (-not (Test-Path -LiteralPath $legacy)) { return }
    if ((Test-Path -LiteralPath $stamp)) { return }

    $legacyMb = Get-CursorRemoteProfileDirSizeMB -Path $legacy
    $targetMb = Get-CursorRemoteProfileDirSizeMB -Path $target
    # Target already has more data than legacy: keep target, archive legacy once.
    if ((Test-Path -LiteralPath $target) -and $targetMb -ge 5 -and $targetMb -ge $legacyMb) {
        try {
            [void](Stop-CursorRemoteProfileProcesses)
            $bakName = "ClaudeServerCursorProfile.bak-keep-$(Get-Date -Format yyyyMMdd)"
            $bak = Join-Path $env:LOCALAPPDATA $bakName
            if (-not (Test-Path -LiteralPath $bak)) {
                Rename-Item -LiteralPath $legacy -NewName $bakName -ErrorAction Stop
            }
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Set-Content -LiteralPath $stamp -Value ("ts={0} action=target_kept legacy_mb={1} target_mb={2}" -f (Get-Date -Format o), $legacyMb, $targetMb) -Encoding ASCII
            if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
                Write-GitModeLog ("CURSOR_PROFILE_MIGRATE action=target_kept site={0} legacy_mb={1} target_mb={2}" -f $site, $legacyMb, $targetMb) 'INFO'
            }
        } catch {
            if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
                Write-GitModeLog ("CURSOR_PROFILE_MIGRATE_SKIP reason=target_kept_locked err={0}" -f $_.Exception.Message) 'WARN'
            }
        }
        return
    }

    # Migrate when target missing, tiny, or clearly smaller than legacy (fresh -Smart after rename).
    $shouldMigrate = (-not (Test-Path -LiteralPath $target)) -or ($targetMb -lt 5) -or ($legacyMb -gt $targetMb)
    if (-not $shouldMigrate) { return }

    try {
        [void](Stop-CursorRemoteProfileProcesses)
        if (Test-Path -LiteralPath $target) {
            $bakSmartName = "$targetName.bak-pre-migrate-$(Get-Date -Format yyyyMMddHHmmss)"
            $bakSmart = Join-Path $env:LOCALAPPDATA $bakSmartName
            try {
                Rename-Item -LiteralPath $target -NewName $bakSmartName -ErrorAction Stop
            } catch {
                New-Item -ItemType Directory -Force -Path $bakSmart | Out-Null
                cmd /c "robocopy `"$target`" `"$bakSmart`" /E /MOVE /R:2 /W:1 /NFL /NDL /NJH /NJS /NC /NS" | Out-Null
                if (Test-Path -LiteralPath $target) {
                    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        try {
            Rename-Item -LiteralPath $legacy -NewName $targetName -ErrorAction Stop
        } catch {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            cmd /c "robocopy `"$legacy`" `"$target`" /E /MOVE /R:3 /W:2 /NFL /NDL /NJH /NJS /NC /NS" | Out-Null
            if (Test-Path -LiteralPath $legacy) {
                Remove-Item -LiteralPath $legacy -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        $finalMb = Get-CursorRemoteProfileDirSizeMB -Path $target
        Set-Content -LiteralPath $stamp -Value ("ts={0} action=rename_legacy_to_target legacy_mb={1} final_mb={2}" -f (Get-Date -Format o), $legacyMb, $finalMb) -Encoding ASCII
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("CURSOR_PROFILE_MIGRATE action=legacy_to_target site={0} legacy_mb={1} final_mb={2}" -f $site, $legacyMb, $finalMb) 'INFO'
        }
    } catch {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("CURSOR_PROFILE_MIGRATE_FAIL err={0}" -f $_.Exception.Message) 'WARN'
        }
    }
}

function Get-CursorWindowTitleTag {
    # Single source of truth for the literal window-title tag text
    # Initialize-CursorServerProfile actually writes for a given site ("Claude Server Smart" /
    # "Claude Server Sepidz"). Shared by Initialize-CursorServerProfile (the writer) and
    # Get-CursorWindowTitleNeedle (the 4 readers, bug 2) so the two can never drift apart again.
    param(
        [string]$Site = (Get-CursorRemoteProfileSite)
    )
    if ($Site -eq 'Sepidz') { return 'Claude Server Sepidz' }
    return 'Claude Server Smart'
}

function Get-CursorWindowTitleNeedle {
    # Bug 2 fix: the 4 window-title match call sites (Test-CursorWindowTitleIsAgentHome,
    # Test-RemoteEditorOnCorrectFolder, Get-RemoteEditorSessionPresence,
    # Get-RemoteEditorStateExplain) used to hardcode the literal regex '\[Claude Server\]', but
    # Initialize-CursorServerProfile has ALWAYS written a site-qualified tag ("[Claude Server
    # Smart]" / "[Claude Server Sepidz]") - the bare, unqualified form is never actually rendered
    # by production code, so that literal regex was permanently dead against every real window.
    # Build the needle dynamically from the SAME Get-CursorWindowTitleTag/
    # Get-CursorRemoteProfileSite source of truth the writer uses, instead of a hand-maintained
    # alternation that could silently drift from it again. The bare '\[Claude Server\]'
    # alternative is kept only as a defensive fallback for a settings.json written to disk before
    # this fix shipped (Initialize-CursorServerProfile never rewrites an existing settings.json,
    # so a pre-existing profile could still carry the old bare-tag title until next profile reset).
    $tag = Get-CursorWindowTitleTag
    return '\[' + [regex]::Escape($tag) + '\]|\[Claude Server\]'
}

function Test-CursorWindowTitleMatchesProject {
    # A server-profile window title belongs to THIS project iff the project's root folder name
    # appears at the exact position the title templates place it, with a trailing non-path boundary:
    #   custom template : "${dirty}${editor}${sep}[Claude Server <Site>] <rootName>"  (root AFTER the tag)
    #   Cursor SSH title: "<...> <rootName> [SSH: <alias>] - Cursor"                   (root BEFORE [SSH:])
    #
    # Matching $rootName ANYWHERE in the title (the old '$title -match $rootNeedle') is wrong on two
    # counts, both hit live 2026-07-25:
    #   1) Site-tag collision: the tag itself is "[Claude Server Smart]", so a project literally named
    #      "smart" matched EVERY open server window - selecting project "smart" foregrounded an
    #      unrelated window and skipped the launch (reason=known_on_folder), so smart never opened.
    #   2) Prefix-sibling collision: a bare/word-boundary substring also matched "smart" inside
    #      "smartdesk" and "ai" inside "ai-gap-summay" (hyphen is a \b boundary), cross-detecting
    #      siblings. Anchor to the template position and require the boundary so "smart" != "smartdesk".
    param(
        [string]$Title,
        [Parameter(Mandatory)][string]$RootName,
        [string]$TitleTag = (Get-CursorWindowTitleTag),
        [string]$AliasNeedleEscaped = ''
    )
    if (-not $Title -or -not $RootName) { return $false }
    $rootEsc = [regex]::Escape($RootName)
    $boundary = '(?![\w./-])'
    if ($Title -match ('\[' + [regex]::Escape($TitleTag) + '\]\s+' + $rootEsc + $boundary)) { return $true }
    # Defensive: a settings.json written before the site-qualified tag shipped uses the bare tag.
    if ($Title -match ('\[Claude Server\]\s+' + $rootEsc + $boundary)) { return $true }
    # Cursor's own default Remote-SSH title places the folder name IMMEDIATELY before the [SSH: <alias>]
    # marker: "<rootName> [SSH: <alias>] - Cursor". The gap here must be whitespace only (\s*), NOT the
    # old greedy [^\[]* - live regression 2026-07-25: with the site-qualified custom title
    # "[Claude Server Smart] refactoreoldclub [SSH: claude-server]", a search for project "smart"
    # case-insensitively matched the "Smart" in the SITE TAG, then [^\[]* skipped across
    # "] refactoreoldclub " to "[SSH:", so on_folder returned TRUE for "smart" even though no smart
    # window was open -> connect skipped the launch and project "smart" never opened. \s* anchors the
    # root right before [SSH:, so the site-tag "Smart" (followed by "]") can no longer reach the marker.
    if ($AliasNeedleEscaped -and
        $Title -match ('(?<![\w./-])' + $rootEsc + $boundary + '\s*\[SSH:\s*' + $AliasNeedleEscaped + '\]')) { return $true }
    return $false
}

function Get-CursorServerWindowTitleTemplate {
    param([string]$TitleTag)
    # The VS Code ${...} tokens MUST reach settings.json literally. The old code built this inside a
    # double-quoted here-string, so PowerShell expanded ${dirty}/${activeEditorShort}/${separator}/
    # ${rootName} to EMPTY - settings.json ended up as "[Claude Server Smart] " with no folder name.
    # Remote windows then never showed the project name, and title-based on_folder / agent-home
    # detection could not tell one project window from another (live regression 2026-07-25: every
    # launch reported failure / "drifted to Agent/home" because the folder was invisible in the title).
    # Build it via string concatenation so the tokens stay literal regardless of quoting.
    return ('${dirty}${activeEditorShort}${separator}[' + $TitleTag + '] ${rootName}')
}

function Repair-CursorServerWindowTitle {
    param(
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$TitleTag
    )
    # In-place repair for profiles created before the here-string bug fix: if window.title is present
    # but lost its ${rootName} token, rewrite ONLY that value (string-level, so JSONC comments / other
    # user settings survive). No-op when the token is already there.
    try {
        if (-not (Test-Path $SettingsPath)) { return $false }
        $raw = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
        if ($raw -notmatch '"window\.title"\s*:\s*"') { return $false }
        if ($raw -match '"window\.title"\s*:\s*"[^"]*\$\{rootName\}') { return $false }
        $correctVal = Get-CursorServerWindowTitleTemplate -TitleTag $TitleTag
        $replacement = '"window.title": "' + $correctVal + '"'
        $new = [regex]::Replace(
            $raw,
            '"window\.title"\s*:\s*"[^"]*"',
            [System.Text.RegularExpressions.MatchEvaluator] { param($m) $replacement },
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if ($new -ne $raw) {
            Set-Content -LiteralPath $SettingsPath -Value $new -Encoding UTF8
            if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                Write-EditorLaunchLog 'PROFILE_REPAIR: window.title restored ${rootName} token' 'INFO'
            }
            return $true
        }
    } catch { }
    return $false
}

function Initialize-CursorServerProfile {
    # First-run: make the server window visually distinct from personal Cursor. On later runs, repair
    # a window.title that lost its ${rootName} token (older here-string bug) so remote windows show the
    # project name and detection can identify them.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    $site = Get-CursorRemoteProfileSite
    $titleTag = Get-CursorWindowTitleTag -Site $site
    if (Test-Path $settingsPath) {
        Repair-CursorServerWindowTitle -SettingsPath $settingsPath -TitleTag $titleTag | Out-Null
        return
    }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    $barBg = if ($site -eq 'Sepidz') { '#3a1e5f' } else { '#1e3a5f' }
    $barBgIn = if ($site -eq 'Sepidz') { '#2a1545' } else { '#152a45' }
    $titleTemplate = Get-CursorServerWindowTitleTemplate -TitleTag $titleTag
    $json = @"
{
  "window.title": "$titleTemplate",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "$barBg",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "$barBgIn",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
"@
    $json | Set-Content -Path $settingsPath -Encoding UTF8
}



function Ensure-CursorRemoteSshQuietSettings {
    # Cursor Remote-SSH on Windows spawns visible cmd.exe pipes for
    # cursor_remote_install_*.sh (one per host). Hide the login terminal so
    # those consoles are not shown after Opening Cursor.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    $obj = $null
    if (Test-Path $settingsPath) {
        try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    $changed = $false
    $prop = $obj.PSObject.Properties['remote.SSH.showLoginTerminal']
    if ($prop) {
        if ($prop.Value -ne $false) { $prop.Value = $false; $changed = $true }
    } else {
        $obj | Add-Member -NotePropertyName 'remote.SSH.showLoginTerminal' -NotePropertyValue $false -Force
        $changed = $true
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog 'CURSOR_SSH_UI: showLoginTerminal=false' 'INFO'
    }
    return $changed
}

function Set-CursorProxySettings {
    # Points Cursor's own network stack (not just extensions) at the local -L forward that
    # git-mode.ps1 opened on the reverse-tunnel ssh process (server xray), so Cursor's
    # chat/agent/MCP requests egress via the VLESS exit IP instead of each laptop's own network.
    # settings.json http.proxy must be http:// (Node/undici rejects socks5); Chromium CLI stays socks5.
    param(
        [int]$SocksPort = 0,
        [int]$HttpPort = 0
    )
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $userDir)) { New-Item -ItemType Directory -Force -Path $userDir | Out-Null }
    if ($HttpPort -gt 0) {
        $proxyUrl = "http://127.0.0.1:$HttpPort"
    } elseif ($SocksPort -gt 0) {
        # Never write socks5 into settings.json: Cursor Node/MCP undici rejects it
        # ("Invalid URL protocol"). Chromium still uses --proxy-server=socks5 via CLI args.
        Write-EditorLaunchLog ("CURSOR_PROXY_SET: skip_settings no_http_leg socks={0} (CLI socks only)" -f $SocksPort) 'WARN'
        return $false
    } else {
        return $false
    }
    $obj = $null
    if (Test-Path $settingsPath) {
        try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $obj = $null }
    }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    $changed = $false
    foreach ($pair in @(
        @{ Name = 'http.proxy'; Value = $proxyUrl }
        @{ Name = 'https.proxy'; Value = $proxyUrl }
        @{ Name = 'http.proxyStrictSSL'; Value = $false }
        @{ Name = 'http.proxySupport'; Value = 'override' }
        @{ Name = 'cursor.general.proxyMode'; Value = 'custom' }
        @{ Name = 'cursor.general.disableHttp2'; Value = $true }
    )) {
        $prop = $obj.PSObject.Properties[$pair.Name]
        if ($prop) {
            if ("$($prop.Value)" -ne "$($pair.Value)") { $prop.Value = $pair.Value; $changed = $true }
        } else {
            $obj | Add-Member -NotePropertyName $pair.Name -NotePropertyValue $pair.Value -Force
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog "CURSOR_PROXY_SET: proxy=$proxyUrl changed=1" 'INFO'
    }
    return $changed
}

function Clear-CursorProxySettings {
    # Remove proxy keys when xray is down or server has no xray (Sepidz) - must match no-feature state.
    $userDir = Join-Path (Get-CursorRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (-not (Test-Path $settingsPath)) { return $false }
    $obj = $null
    try { $obj = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if (-not $obj) { return $false }
    $changed = $false
    foreach ($key in @('http.proxy', 'https.proxy', 'http.proxyStrictSSL', 'http.proxySupport', 'cursor.general.proxyMode', 'cursor.general.disableHttp2')) {
        $prop = $obj.PSObject.Properties[$key]
        if ($prop) {
            $obj.PSObject.Properties.Remove($key)
            $changed = $true
        }
    }
    if ($changed) {
        ($obj | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding UTF8
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: removed proxy keys changed=1' 'INFO'
    }
    return $changed
}

function Get-RunningCursorProxyCliPort {
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        try {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ProcessId)" -ErrorAction Stop
            $cmd = [string]$cim.CommandLine
            if ($cmd -match '--proxy-server=socks5://127\.0\.0\.1:(\d+)') {
                return [int]$Matches[1]
            }
        } catch {}
    }
    return 0
}

function Align-CursorProxyWithRunningCli {
    param([int]$SocksPort = 0, [int]$HttpPort = 0)
    $cliPort = Get-RunningCursorProxyCliPort
    $frontSocks = 0
    if ($script:CursorSocksFrontPort) { $frontSocks = [int]$script:CursorSocksFrontPort }
    # Sticky front (18999) wins over a live CLI still pinned to backend 19080.
    # Old windows keep their --proxy-server until relaunch; do NOT drag settings/launch
    # args back down to the backend port (defeats sidecar across tunnel reseed).
    if ($frontSocks -gt 0 -and $cliPort -gt 0 -and $cliPort -ne $frontSocks) {
        $frontUp = $false
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-LocalPortOpen -PortNum $frontSocks)
        } elseif (Get-Command Test-CursorProxySidecarListening -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-CursorProxySidecarListening -Port $frontSocks)
        }
        if ($frontUp) {
            Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_sticky_front socks={0} cli_legacy={1} (relaunch picks up front)" -f $frontSocks, $cliPort) 'INFO'
            $http = $HttpPort
            if ($script:CursorHttpFrontPort) { $http = [int]$script:CursorHttpFrontPort }
            return @{ Aligned = $true; SocksPort = $frontSocks; HttpPort = $http; LegacyCli = $cliPort }
        }
    }
    if ($cliPort -le 0) { return @{ Aligned = $false; SocksPort = $SocksPort; HttpPort = $HttpPort } }
    if ($SocksPort -gt 0 -and $cliPort -ne $SocksPort) {
        Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_running_cli socks={0} session={1}" -f $cliPort, $SocksPort) 'INFO'
        return @{ Aligned = $true; SocksPort = $cliPort; HttpPort = $HttpPort }
    }
    if ($cliPort -gt 0) {
        Write-EditorLaunchLog ("CURSOR_PROXY_ALIGN: prefer_running_cli socks={0} session={1}" -f $cliPort, $SocksPort) 'DEBUG'
    }
    return @{ Aligned = $true; SocksPort = $cliPort; HttpPort = $HttpPort }
}

function Test-MayClearCursorProxySettings {
    param([switch]$AllowClear)
    if ($null -ne $script:CursorProxyOwner -and -not $script:CursorProxyOwner) {
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=non_owner' 'INFO'
        return $false
    }
    $n = 0
    try { $n = @(Get-CursorProfileProcesses).Count } catch { $n = 0 }
    if ($n -gt 0) {
        Write-EditorLaunchLog ("CURSOR_PROXY_CLEAR_SKIP: reason=windows_open socks_null=1 profile_count={0}" -f $n) 'INFO'
        return $false
    }
    if (-not $AllowClear) {
        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=no_allow_clear' 'DEBUG'
        return $false
    }
    return $true
}

function Get-CodeRemoteProfileDir {
    # Isolated VS Code profile for server Remote-SSH (parity with Mac ClaudeServerCodeProfile).
    return (Join-Path $env:LOCALAPPDATA 'ClaudeServerCodeProfile')
}

function Initialize-CodeServerProfile {
    $userDir = Join-Path (Get-CodeRemoteProfileDir) 'User'
    $settingsPath = Join-Path $userDir 'settings.json'
    if (Test-Path $settingsPath) { return }
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    }
    @'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server Code] ${rootName}",
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
'@ | Set-Content -Path $settingsPath -Encoding UTF8
}

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

function Show-EditorAutoPick {
    param(
        [Parameter(Mandatory)][string]$PickedName,
        [Parameter(Mandatory)][string]$OtherName,
        [Parameter(Mandatory)][string]$OtherReason
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host "    $PickedName  <- only option, opening automatically" -ForegroundColor DarkGray
    Write-Host "    $OtherName  (unavailable - $OtherReason)" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    if (-not (Test-Path $EditorPrefFile)) { return 'cursor' }
    $saved = (Get-Content $EditorPrefFile -Raw -ErrorAction SilentlyContinue).Trim().ToLower()
    if ($saved -eq 'vscode') { $saved = 'code' }
    if ($saved -match '^(rider|both)$') { Remove-Item $EditorPrefFile -ErrorAction SilentlyContinue; return 'cursor' }
    if ($saved -in @('cursor', 'code', 'ask')) { return $saved }
    return 'cursor'
}

function Show-EditorPickMenu {
    param(
        [Parameter(Mandatory)][string]$CfgDir,
        [string]$Saved = 'cursor',
        [switch]$PersistChoice
    )
    Write-Host ''
    Write-Host '    Open with' -ForegroundColor White
    Write-Host ''
    Write-Host '    1  Cursor' -ForegroundColor DarkGray
    Write-Host '    2  VS Code' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "    (Enter = $Saved)" -ForegroundColor DarkGray
    $edChoice = (Read-Host '    >').Trim().ToLower()
    $EditorCmd = 'cursor'
    $EditorName = 'Cursor'
    switch ($edChoice) {
        { $_ -in '1', 'cursor', 'c' } { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        '' {
            if ($Saved -eq 'code') { $EditorCmd = 'code'; $EditorName = 'VS Code' }
        }
        default { $EditorCmd = 'cursor'; $EditorName = 'Cursor' }
    }
    if ($PersistChoice) {
        $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
        Set-Content -Path $EditorPrefFile -Value $EditorCmd -Encoding ASCII | Out-Null
    }
    return ,([PSCustomObject]@{ EditorCmd = $EditorCmd; EditorName = $EditorName })
}

function Configure-EditorPref {
    param([Parameter(Mandatory)][string]$CfgDir)
    Write-Host ''
    Write-Host '    IDE preference' -ForegroundColor White
    Write-Host ''
    $cur = Get-EditorPref -CfgDir $CfgDir
    Write-Host "    Current: $cur" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    1  cursor - always open Cursor' -ForegroundColor DarkGray
    Write-Host '    2  code   - always open VS Code' -ForegroundColor DarkGray
    Write-Host '    3  ask    - pick each connect' -ForegroundColor DarkGray
    Write-Host ''
    $choice = (Read-Host '    >').Trim().ToLower()
    $val = switch ($choice) {
        { $_ -in '1', 'cursor', 'c' } { 'cursor' }
        { $_ -in '2', 'code', 'vscode', 'v' } { 'code' }
        { $_ -in '3', 'ask', 'a' } { 'ask' }
        default { $null }
    }
    if (-not $val) { Warn 'Invalid choice.'; return }
    Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value $val -Encoding ASCII | Out-Null
    Write-Host "    Saved: $val" -ForegroundColor Green
    Write-Host ''
}

function Resolve-EditorChoice {
    param(
        [Parameter(Mandatory)][string]$CfgDir
    )

    # Path.Combine - Join-Path binds pipeline input and causes ChildPath prompt
    $EditorPrefFile = [System.IO.Path]::Combine($CfgDir, 'editor.conf')
    Ensure-EditorOnPath 'cursor' | Out-Null
    Ensure-EditorOnPath 'code' | Out-Null
    $haveCursor = [bool](Get-Command cursor -ErrorAction SilentlyContinue)
    $haveCode   = [bool](Get-Command code   -ErrorAction SilentlyContinue)

    if (-not $haveCursor -and -not $haveCode) {
        return $null
    }

    if ($haveCursor -and -not $haveCode) {
        Show-EditorAutoPick -PickedName 'Cursor' -OtherName 'VS Code' -OtherReason 'not installed, or missing the Remote-SSH extension'
        return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
    }
    if (-not $haveCursor -and $haveCode) {
        Show-EditorAutoPick -PickedName 'VS Code' -OtherName 'Cursor' -OtherReason 'not installed, or install is broken'
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }

    $pref = Get-EditorPref -CfgDir $CfgDir
    if ($pref -eq 'ask') {
        return ,@(Show-EditorPickMenu -CfgDir $CfgDir -Saved 'cursor' -PersistChoice)[-1]
    }
    if ($pref -eq 'code') {
        return ,([PSCustomObject]@{ EditorCmd = 'code'; EditorName = 'VS Code' })
    }
    return ,([PSCustomObject]@{ EditorCmd = 'cursor'; EditorName = 'Cursor' })
}

function Test-IsElevatedShell {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveWindowsUser {
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}

function Get-InteractiveWindowsUserQualified {
    # schtasks /RU needs DOMAIN\user (short "User" is ambiguous / often fails /IT).
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner -and ($owner -match '\\')) { return $owner }
        if ($owner) { return "$env:COMPUTERNAME\$owner" }
    } catch {}
    $u = Get-InteractiveWindowsUser
    if ($u -match '\\') { return $u }
    return "$env:COMPUTERNAME\$u"
}

function Get-EditorNativeExe {
    param([Parameter(Mandatory)][string]$EditorCmd)
    $cli = Ensure-EditorOnPath $EditorCmd
    if (-not $cli) { return $null }
    if ($EditorCmd -ne 'cursor') { return $cli }
    if ($cli -match '\\Cursor\.exe$') { return $cli }
    $binDir = Split-Path $cli -Parent
    $root = Split-Path (Split-Path (Split-Path $binDir -Parent) -Parent) -Parent
    $exe = Join-Path $root 'Cursor.exe'
    if (Test-Path $exe) { return $exe }
    return $cli
}

function Show-ConnectConsoleIfHidden {
    try {
        if (-not ('Win32.ConnectConsole' -as [type])) {
            Add-Type -Name ConnectConsole -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        }
        [Win32.ConnectConsole]::ShowWindow([Win32.ConnectConsole]::GetConsoleWindow(), 5) | Out-Null
    } catch {}
}

function Stop-CursorServerProfileTree {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    $procs = @(Get-CursorProfileProcesses -ProfileDir $ProfileDir)
    if ($procs.Count -eq 0) { return }
    $seen = @{}
    foreach ($p in $procs) {
        if ($seen[$p.ProcessId]) { continue }
        $seen[$p.ProcessId] = $true
        $cmd = Format-EditorProcessCommandLine -CommandLine $p.CommandLine -MaxLen 120
        Write-EditorLaunchLog "LAUNCH_KILL_PROC: pid=$($p.ProcessId) cmd=$cmd" 'DEBUG'
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 200
}

function Initialize-NonElevatedLauncher {
    if ($script:NonElevatedLauncherReady) { return }
    if (-not ('NonElevatedLauncher' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class NonElevatedLauncher
{
    // PROCESS_QUERY_LIMITED_INFORMATION works on Win10/11 when full QUERY is denied.
    const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const uint TOKEN_DUPLICATE = 0x0002;
    const uint TOKEN_QUERY = 0x0008;
    const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
    const int SecurityImpersonation = 2;
    const int TokenPrimary = 1;
    const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    // Hard-detach from parent console so Cursor Electron/Node stderr cannot flood connect.bat.
    const uint DETACHED_PROCESS = 0x00000008;
    const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;
    const int SW_SHOW = 5;
    public static int LastWin32Error;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool DuplicateTokenEx(IntPtr hExisting, uint dwDesiredAccess, IntPtr lpTokenAttributes, int ImpersonationLevel, int TokenType, out IntPtr phNewToken);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr hToken, uint dwLogonFlags, string lpApplicationName, StringBuilder lpCommandLine, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    static Process FindExplorer() {
        int sid = Process.GetCurrentProcess().SessionId;
        foreach (Process p in Process.GetProcessesByName("explorer")) {
            if (p.SessionId == sid) { return p; }
        }
        return null;
    }

    public static bool Start(string file, string args) {
        LastWin32Error = 0;
        Process explorer = FindExplorer();
        if (explorer == null) { LastWin32Error = 2; return false; }
        IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, explorer.Id);
        if (hProc == IntPtr.Zero) {
            hProc = OpenProcess(PROCESS_QUERY_INFORMATION, false, explorer.Id);
        }
        if (hProc == IntPtr.Zero) { LastWin32Error = Marshal.GetLastWin32Error(); return false; }
        IntPtr hTok;
        if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY, out hTok)) {
            LastWin32Error = Marshal.GetLastWin32Error();
            CloseHandle(hProc);
            return false;
        }
        IntPtr hDup;
        if (!DuplicateTokenEx(hTok, TOKEN_ASSIGN_PRIMARY | TOKEN_DUPLICATE | TOKEN_QUERY, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out hDup)) {
            LastWin32Error = Marshal.GetLastWin32Error();
            CloseHandle(hTok);
            CloseHandle(hProc);
            return false;
        }
        CloseHandle(hTok);
        CloseHandle(hProc);
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = "winsta0\\default";
        si.dwFlags = 1;
        si.wShowWindow = SW_SHOW;
        PROCESS_INFORMATION pi;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        // LOGON_WITH_PROFILE (1): load user hive. Do NOT set CREATE_UNICODE_ENVIRONMENT with
        // null env (that can inherit the elevated block and break GUI apps).
        // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP: isolate from elevated parent console;
        // SW_SHOW still shows the GUI window.
        const uint LOGON_WITH_PROFILE = 0x00000001;
        uint creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
        bool ok = CreateProcessWithTokenW(hDup, LOGON_WITH_PROFILE, null, cmd, creationFlags, IntPtr.Zero, null, ref si, out pi);
        if (!ok) { LastWin32Error = Marshal.GetLastWin32Error(); }
        CloseHandle(hDup);
        if (ok) {
            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }
        return ok;
    }
}
'@ -ErrorAction Stop
    }
    $script:NonElevatedLauncherReady = $true
}

function Invoke-SchTasksQuiet {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ArgumentList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'schtasks.exe'
    $psi.Arguments = (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$p.StandardOutput.ReadToEnd()
    [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return $p.ExitCode
}

function Initialize-EditorLaunchTask {
    if ($script:EditorLaunchTaskReady) { return $true }
    $taskName = 'ClaudeServerEditorLaunch'
    $dir = Join-Path $env:LOCALAPPDATA 'ClaudeConnect'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $helper = Join-Path $dir 'launch-editor.ps1'
    @'
$ErrorActionPreference = "Stop"
$log = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-editor.log"
function Write-LaunchHelperLog([string]$m) {
  try {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -LiteralPath $log -Value "[$ts] $m" -Encoding UTF8
  } catch {}
}
try {
  $specPath = Join-Path $env:LOCALAPPDATA "ClaudeConnect\launch-spec.json"
  $spec = Get-Content $specPath -Raw | ConvertFrom-Json
  $args = @()
  if ($spec.Args) { $args = @([string[]]$spec.Args) }
  Write-LaunchHelperLog ("start exe=" + $spec.FilePath + " argc=" + $args.Count)
  $p = Start-Process -FilePath $spec.FilePath -ArgumentList $args -WindowStyle Normal -PassThru
  Write-LaunchHelperLog ("started pid=" + $p.Id)
} catch {
  Write-LaunchHelperLog ("FAIL " + $_.Exception.Message)
  exit 1
}
exit 0
'@ | Set-Content -Path $helper -Encoding UTF8
    $user = Get-InteractiveWindowsUserQualified
    Write-EditorLaunchLog "LAUNCH_TASK: recreate RU=$user" 'DEBUG'
    $tr = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helper`""
    if ((Invoke-SchTasksQuiet /Query /TN $taskName) -eq 0) {
        [void](Invoke-SchTasksQuiet /Delete /F /TN $taskName)
    }
    $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $user /RL LIMITED /IT
    if ($createExit -ne 0) {
        # Fallback: short name (older hosts)
        $short = Get-InteractiveWindowsUser
        Write-EditorLaunchLog "LAUNCH_TASK: qualified RU failed exit=$createExit; retry RU=$short" 'WARN'
        $createExit = Invoke-SchTasksQuiet /Create /F /TN $taskName /TR $tr /SC ONCE /ST 00:00 /RU $short /RL LIMITED /IT
    }
    $script:EditorLaunchTaskReady = ($createExit -eq 0)
    if (-not $script:EditorLaunchTaskReady) {
        Write-EditorLaunchLog "LAUNCH_TASK: create failed exit=$createExit" 'WARN'
    }
    return $script:EditorLaunchTaskReady
}

function Start-ProcessViaLaunchTask {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    if (-not (Initialize-EditorLaunchTask)) { return $false }
    $specPath = Join-Path $env:LOCALAPPDATA 'ClaudeConnect\launch-spec.json'
    @{ FilePath = $FilePath; Args = $ArgumentList } | ConvertTo-Json -Compress | Set-Content -Path $specPath -Encoding UTF8
    return ((Invoke-SchTasksQuiet /Run /TN 'ClaudeServerEditorLaunch') -eq 0)
}

function Format-ProcessArgumentString {
    param([string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object {
        if ($null -eq $_) { return '' }
        $s = [string]$_
        if ($s -match '\s') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }) -join ' ')
}


function Get-EditorExeNameFromPath {
    param([Parameter(Mandatory)][string]$FilePath)
    $leaf = Split-Path $FilePath -Leaf
    if ($leaf -match '(?i)^cursor(\.exe|\.cmd)?$') { return 'Cursor.exe' }
    if ($leaf -match '(?i)^code(\.exe|\.cmd)?$') { return 'Code.exe' }
    if ($leaf -match '\.exe$') { return $leaf }
    return $null
}

function Get-EditorProfileDirFromArgs {
    param([string[]]$ArgumentList = @())
    for ($i = 0; $i -lt ($ArgumentList.Count - 1); $i++) {
        if ($ArgumentList[$i] -eq '--user-data-dir') { return $ArgumentList[$i + 1] }
    }
    return $null
}

function Test-EditorProcessEvidence {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutMs = 2000
    )
    $exeName = Get-EditorExeNameFromPath -FilePath $FilePath
    if (-not $exeName) { return $false }
    $profileDir = Get-EditorProfileDirFromArgs -ArgumentList $ArgumentList
    $profileNeedle = if ($profileDir) { [regex]::Escape($profileDir) } else { $null }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        $procs = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'proc_start_verify' -ForceRefresh)
        if ($profileNeedle) {
            $procs = @($procs | Where-Object { $_.CommandLine -and ($_.CommandLine -match $profileNeedle) })
        }
        if ($procs.Count -gt 0) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Get-EditorProfileProcessesForLaunch {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [switch]$ForceRefresh
    )
    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } else { Get-CodeRemoteProfileDir }
    if (-not $profileDir) { return @() }
    $needle = [regex]::Escape($profileDir)
    return @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'launch_profile_verify' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Confirm-RemoteEditorLaunchVisible {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        # Warm ×6: single 500ms recheck missed handoff flicker (Precise 20260804.17 dakhl).
        [int]$WaitMs = 3000
    )
    # Project-scoped only. Never treat "any Cursor MainWindowHandle on the profile" as
    # confirmation - that false-positive skipped Launch-RemoteEditor (known_on_folder) while
    # the user only had Agents / another project / personal Cursor visible (live 2026-07-28).
    # Success bar is on_folder only - MUST match Launch-RemoteEditor (P0.4: window-count-alone
    # used to return true from Launch while Confirm rejected it -> false "elevated launch failed").
    if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
    if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    if ($WaitMs -le 0) { return $false }
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while ($deadline.ElapsedMilliseconds -lt $WaitMs) {
        Start-Sleep -Milliseconds 250
        if (Get-Command Clear-CursorProcessCache -ErrorAction SilentlyContinue) { Clear-CursorProcessCache }
        if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) { return $true }
    }
    return $false
}

function Get-RemoteEditorLaunchFailMessage {
    param([Parameter(Mandatory)][string]$EditorName)
    # Reflect the actual shell elevation. Hardcoding "elevated launch failed" misled users
    # on non-elevated Connect (all 11 Aug-1 false fails logged elevated=False).
    $elevated = $false
    try { $elevated = [bool](Test-IsElevatedShell) } catch { $elevated = $false }
    if ($elevated) {
        return "elevated launch failed - no $EditorName window on project folder (try non-elevated Connect or check $EditorName install)"
    }
    return "$EditorName launch did not show the project folder window (check $EditorName install or press O to retry)"
}

function Stop-EditorLaunchAttemptOrphans {
    param(
        [int[]]$KeepPids = @(),
        [int[]]$CandidatePids = @()
    )
    # Reap Cursor.exe PIDs spawned by losing launch strategies once a winner is confirmed.
    # Never touch baseline / keep-list PIDs (shared-profile windows must stay alive).
    $keepSet = @{}
    foreach ($k in @($KeepPids)) {
        if ($k -gt 0) { $keepSet[[int]$k] = $true }
    }
    $reaped = 0
    foreach ($cand in @($CandidatePids | Select-Object -Unique)) {
        $pidNum = [int]$cand
        if ($pidNum -le 0) { continue }
        if ($keepSet.ContainsKey($pidNum)) { continue }
        try {
            $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
            if (-not $proc) { continue }
            Stop-Process -Id $pidNum -Force -ErrorAction SilentlyContinue
            $reaped++
            Write-EditorLaunchLog ("LAUNCH_REAP_ORPHAN: pid={0} name={1}" -f $pidNum, $proc.ProcessName) 'INFO'
        } catch {
            Write-EditorLaunchLog ("LAUNCH_REAP_ORPHAN_FAIL: pid={0} ex={1}" -f $pidNum, $_.Exception.Message) 'DEBUG'
        }
    }
    if ($reaped -gt 0) {
        Write-EditorLaunchLog ("LAUNCH_REAP_ORPHAN_DONE: count={0}" -f $reaped) 'INFO'
    }
    return $reaped
}

function Get-CursorLaunchDayLogPath {
    $logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    return (Join-Path $logDir ("cursor-launch-{0}.log" -f (Get-Date -Format 'yyyyMMdd')))
}

function Initialize-EditorDetachedLaunch {
    if ($script:EditorDetachedLaunchReady) { return }
    if (-not ('EditorDetachedLaunch' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class EditorDetachedLaunch
{
    public const uint DETACHED_PROCESS = 0x00000008;
    public const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;
    public const uint CREATE_NO_WINDOW = 0x08000000;
    const int STARTF_USESHOWWINDOW = 0x00000001;
    const int STARTF_USESTDHANDLES = 0x00000100;
    const short SW_SHOW = 5;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint CREATE_ALWAYS = 2;
    const uint FILE_ATTRIBUTE_NORMAL = 0x80;

    public static int LastWin32Error;

    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public bool bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize;
        public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
        public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION {
        public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string lpApplicationName, StringBuilder lpCommandLine,
        IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles,
        uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        ref SECURITY_ATTRIBUTES lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    static IntPtr OpenInheritWrite(string path) {
        SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES();
        sa.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
        sa.bInheritHandle = true;
        IntPtr h = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
            ref sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (h == new IntPtr(-1)) { LastWin32Error = Marshal.GetLastWin32Error(); }
        return h;
    }

    // Direct Cursor/VS Code launch: CreateProcessW (no cmd.exe), argv intact, stdio to day logs,
    // DETACHED_PROCESS so connect console is never flooded. GUI still shows (SW_SHOW).
    public static int Start(string file, string args, string stdoutPath, string stderrPath, uint creationFlags) {
        LastWin32Error = 0;
        IntPtr hOut = OpenInheritWrite(stdoutPath);
        if (hOut == new IntPtr(-1)) { return 0; }
        IntPtr hErr = OpenInheritWrite(stderrPath);
        if (hErr == new IntPtr(-1)) {
            CloseHandle(hOut);
            return 0;
        }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
        si.wShowWindow = SW_SHOW;
        si.hStdInput = IntPtr.Zero;
        si.hStdOutput = hOut;
        si.hStdError = hErr;
        StringBuilder cmd = new StringBuilder(32768);
        cmd.Append('"');
        cmd.Append(file);
        cmd.Append('"');
        if (!string.IsNullOrEmpty(args)) {
            cmd.Append(' ');
            cmd.Append(args);
        }
        PROCESS_INFORMATION pi;
        bool ok = CreateProcessW(file, cmd, IntPtr.Zero, IntPtr.Zero, true, creationFlags,
            IntPtr.Zero, null, ref si, out pi);
        if (!ok) { LastWin32Error = Marshal.GetLastWin32Error(); }
        CloseHandle(hOut);
        CloseHandle(hErr);
        if (!ok) { return 0; }
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return pi.dwProcessId;
    }
}
'@ -ErrorAction Stop
    }
    $script:EditorDetachedLaunchReady = $true
}

function Start-EditorProcessDirect {
    # Canonical Cursor/VS Code launch: CreateProcessW with ArgumentList argv (no cmd.exe wrap).
    # Warm --remote IPC handoff requires a direct Cursor.exe process - NOT cmd /C Quiet wrap.
    #
    # Stdio: Cursor's Node/Electron dumps DeprecationWarning / "disable-http2 is not in the list
    # of known options" / "Error mutex already exists" to the *parent console* when the child
    # inherits it. RedirectStandardOutput / RedirectStandardError to cursor-launch day logs, set
    # ELECTRON_NO_ATTACH_CONSOLE, AND hard-detach (DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
    # so connect stays clean without the Quiet wrap that broke IPC.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $logPath = Get-CursorLaunchDayLogPath
    $stdoutPath = $logPath -replace '\.log$', '.stdout.log'
    $stderrPath = $logPath -replace '\.log$', '.stderr.log'
    try {
        $stamp = '---- {0} pid-parent={1} ----' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $PID
        Add-Content -LiteralPath $logPath -Value $stamp -Encoding UTF8
    } catch { }

    $prevNoAttach = $env:ELECTRON_NO_ATTACH_CONSOLE
    $prevNoWarn = $env:NODE_NO_WARNINGS
    $env:ELECTRON_NO_ATTACH_CONSOLE = '1'
    $env:NODE_NO_WARNINGS = '1'
    try {
        Initialize-EditorDetachedLaunch
        $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
        # RedirectStandardOutput / RedirectStandardError targets (day logs); Start-Process cannot
        # set DETACHED_PROCESS, so CreateProcessW opens those files with STARTF_USESTDHANDLES.
        $RedirectStandardOutput = $stdoutPath
        $RedirectStandardError = $stderrPath
        $creationFlags = [uint32]([EditorDetachedLaunch]::DETACHED_PROCESS -bor `
            [EditorDetachedLaunch]::CREATE_NEW_PROCESS_GROUP -bor `
            [EditorDetachedLaunch]::CREATE_NO_WINDOW)
        $procId = [EditorDetachedLaunch]::Start(
            $FilePath, $argStr, $RedirectStandardOutput, $RedirectStandardError, $creationFlags)
        if ($procId -le 0) {
            throw ("EditorDetachedLaunch CreateProcessW failed win32={0}" -f [EditorDetachedLaunch]::LastWin32Error)
        }
        return [System.Diagnostics.Process]::GetProcessById($procId)
    } finally {
        if ($null -eq $prevNoAttach) { Remove-Item Env:\ELECTRON_NO_ATTACH_CONSOLE -ErrorAction SilentlyContinue }
        else { $env:ELECTRON_NO_ATTACH_CONSOLE = $prevNoAttach }
        if ($null -eq $prevNoWarn) { Remove-Item Env:\NODE_NO_WARNINGS -ErrorAction SilentlyContinue }
        else { $env:NODE_NO_WARNINGS = $prevNoWarn }
    }
}

function Start-ProcessAsInteractiveUser {    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $script:LastEditorStartPid = 0
    $argPreview = Format-ProcessArgumentString -ArgumentList $ArgumentList
    if (-not (Test-IsElevatedShell)) {
        Write-EditorLaunchLog "PROC_START: mode=non_elevated_direct exe=$FilePath args=$argPreview" 'DEBUG'
        try {
            $p = Start-EditorProcessDirect -FilePath $FilePath -ArgumentList $ArgumentList
            if (-not $p) {
                Write-EditorLaunchLog 'PROC_START_FAIL: mode=non_elevated_direct Start-Process returned null' 'ERROR'
                return $false
            }
            $script:LastEditorStartPid = [int]$p.Id
            Write-EditorLaunchLog ("PROC_START_OK: mode=non_elevated_direct pid={0}" -f $p.Id) 'DEBUG'
            return $true
        } catch {
            Write-EditorLaunchLog ("PROC_START_FAIL: mode=non_elevated_direct ex={0}" -f $_.Exception.Message) 'ERROR'
            return $false
        }
    }
    Write-EditorLaunchLog "PROC_START: mode=elevated exe=$FilePath args=$argPreview" 'DEBUG'
    # Refresh the scheduled task once per connect run (so RU/helper fixes apply after an
    # update) - NOT on every launch attempt. Launch-RemoteEditor tries up to 4 strategies
    # per call, and this path can be re-entered many times per session (retries, auth
    # relaunch, O to reopen). Resetting EditorLaunchTaskReady unconditionally forced a
    # /Delete + /Create of ClaudeServerEditorLaunch on every single attempt; deleting the
    # task definition while a just-triggered instance could still be mid-run detached that
    # instance from Task Scheduler's lifecycle tracking, leaking a powershell.exe host
    # process per attempt (confirmed: dozens of stale launch-editor.ps1 processes still
    # alive hours later in the same session).
    if (-not $script:EditorLaunchTaskRefreshedThisRun) {
        $script:EditorLaunchTaskReady = $false
        $script:EditorLaunchTaskRefreshedThisRun = $true
    }
    Initialize-NonElevatedLauncher
    $argStr = Format-ProcessArgumentString -ArgumentList $ArgumentList
    # Keep interactive attempts short: Aria/Mehrdad spent ~17s on Opening Cursor when
    # NonElevated+Task both failed before elevated_direct_fallback (which works).
    $evidenceMsNe = 2500
    $evidenceMsTask = 4000
    $evidenceMsDirect = 8000
    $neStarted = $false
    try {
        if ([NonElevatedLauncher]::Start($FilePath, $argStr)) {
            $neStarted = $true
            if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsNe) {
                Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_non_elevated_launcher' 'DEBUG'
                return $true
            }
            Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_non_elevated_launcher no_process' 'DEBUG'
        } else {
            $winErr = 0
            try { $winErr = [NonElevatedLauncher]::LastWin32Error } catch {}
            Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_non_elevated_launcher Start=false win32=$winErr" 'DEBUG'
        }
    } catch {
        Write-EditorLaunchLog "PROC_START_WARN: NonElevatedLauncher exception=$($_.Exception.Message)" 'WARN'
    }
    # The LIMITED scheduled task is an independent non-admin path. Try it even when
    # CreateProcessWithTokenW returns false (including access denied / win32=5).
    if (Start-ProcessViaLaunchTask -FilePath $FilePath -ArgumentList $ArgumentList) {
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsTask) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_launch_task' 'DEBUG'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task no_process' 'WARN'
    } else {
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_launch_task schtasks_failed' 'WARN'
    }
    # Last resort: start from the elevated token via DIRECT Start-Process (not cmd Quiet wrap -
    # Quiet breaks Electron warm IPC handoff). Prefer interactive NonElevated/Task paths above.
    try {
        Write-EditorLaunchLog 'PROC_START: mode=elevated_direct_fallback' 'DEBUG'
        Start-EditorProcessDirect -FilePath $FilePath -ArgumentList $ArgumentList | Out-Null
        if (Test-EditorProcessEvidence -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutMs $evidenceMsDirect) {
            Write-EditorLaunchLog 'PROC_START_OK: mode=elevated_direct_fallback' 'DEBUG'
            return $true
        }
        Write-EditorLaunchLog 'PROC_START_FAIL: mode=elevated_direct_fallback no_process' 'ERROR'
    } catch {
        Write-EditorLaunchLog "PROC_START_FAIL: mode=elevated_direct_fallback ex=$($_.Exception.Message)" 'ERROR'
    }
    return $false
}

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0
$script:VerboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')

function Clear-CursorProcessCache {
    $script:EditorCimCache = @{}
}

function Test-LaunchPerfEnabled {
    if (Get-Command Test-ConnectPerfEnabled -ErrorAction SilentlyContinue) {
        return [bool](Test-ConnectPerfEnabled)
    }
    # Keep the standalone fallback aligned with connect-ui.ps1: PERF is opt-in.
    return ($env:CLAUDE_CONNECT_PERF_LOG -eq '1')
}

function Write-LaunchPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = ''
    )
    if (-not (Test-LaunchPerfEnabled)) { return }
    $cim = if ($null -ne $script:LaunchCimCallCount) { $script:LaunchCimCallCount } else { 0 }
    $fullExtra = "cim_total=$cim" + $(if ($Extra) { " $Extra" } else { '' })
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark $Mark -Ms $Ms -Extra $fullExtra
    } else {
        Write-EditorLaunchLog "PERF[$Mark] ms=$Ms $fullExtra" 'DEBUG'
    }
}

function Invoke-CimEditorProcessQuery {
    param(
        [Parameter(Mandatory)][string]$ExeName,
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    if ($null -eq $script:LaunchCimCallCount) { $script:LaunchCimCallCount = 0 }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Bug 48: TTL so closed editors are detected (cache must expire).
    if (-not $script:EditorCimCacheTtlSec) { $script:EditorCimCacheTtlSec = 2 }
    if (-not $ForceRefresh -and $script:EditorCimCache.ContainsKey($ExeName)) {
        $entry = $script:EditorCimCache[$ExeName]
        $cached = $null
        $ageOk = $false
        if ($entry -is [hashtable] -and $entry.ContainsKey('At') -and $entry.ContainsKey('Procs')) {
            $ageOk = ((Get-Date) - [datetime]$entry.At).TotalSeconds -lt [double]$script:EditorCimCacheTtlSec
            $cached = @($entry.Procs)
        } else {
            # Legacy bare array entry - treat as expired.
            $cached = @($entry)
            $ageOk = $false
        }
        if ($ageOk) {
            $sw.Stop()
            Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($cached.Count) cache_hit=1 exe=$ExeName"
            return $cached
        }
    }
    $result = @(Get-CimInstance Win32_Process -Filter "Name='$ExeName'" -Property ProcessId,Name,CommandLine -ErrorAction SilentlyContinue)
    $script:EditorCimCache[$ExeName] = @{ At = Get-Date; Procs = $result }
    $script:LaunchCimCallCount++
    $sw.Stop()
    Write-LaunchPerfLog -Mark 'cim_query' -Ms $sw.ElapsedMilliseconds -Extra "reason=$Reason count=$($result.Count) cache_hit=0 exe=$ExeName"
    return $result
}

function Invoke-CimCursorProcessQuery {
    param(
        [string]$Reason = 'unspecified',
        [switch]$ForceRefresh
    )
    return @(Invoke-CimEditorProcessQuery -ExeName 'Cursor.exe' -Reason $Reason -ForceRefresh:$ForceRefresh)
}

function Get-CursorProfileProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $needle = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'profile_procs' -ForceRefresh:$ForceRefresh |
        Where-Object { $_.CommandLine -and ($_.CommandLine -match $needle) })
}

function Test-PathNeedleBoundaryMatch {
    # Boundary-safe substring check: NeedleEscaped must match exactly, or be immediately
    # followed by a path separator / quote character / whitespace, or end-of-string. A bare
    # substring test wrongly matches a shorter project path inside a longer one that shares the
    # same prefix (e.g. ".../ai-gap" incorrectly matching inside ".../ai-gap-summay"). Whitespace
    # must be in the allowed boundary set too: the OS-reported CommandLine for a Cursor process
    # can have a trailing/inter-argument space right after the path, which is not one of
    # \/"' or end-of-string - confirmed live (a real --folder-uri process had a trailing space
    # after the path and this check false-negatived, breaking on-folder detection).
    param(
        [string]$CommandLine,
        [Parameter(Mandatory)][string]$NeedleEscaped
    )
    if (-not $CommandLine) { return $false }
    return [bool]($CommandLine -match "$NeedleEscaped(?:[\\/`"'\s]|$)")
}

# .NET Process.MainWindowHandle / .MainWindowTitle only ever reflect ONE window per
# process - specifically whichever top-level window of that process is currently topmost
# in the system-wide Z-order. Cursor is a single-instance Electron app: all windows that
# share the ClaudeServerCursorProfile profile live inside ONE OS process, and when Cursor's
# IPC opens a brand-new window for a different project in that same already-running
# process, MainWindowHandle/MainWindowTitle keep reporting whichever window was already
# topmost (typically the pre-existing one) - the new window is completely invisible to any
# check built only on those two properties, even though it is a real, valid top-level
# window of the target PID. EnumWindows walks every top-level window on the desktop
# directly, so filtering by owning PID finds ALL of a process's windows, not just the
# Z-order-topmost one.
function Initialize-Win32WindowEnum {
    if ($script:Win32WindowEnumReady) { return }
    if (-not ('ClaudeConnectWin32Window' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ClaudeConnectWin32Window
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(int idAttach, int idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern int GetCurrentThreadId();
}
'@ -ErrorAction Stop
    }
    $script:Win32WindowEnumReady = $true
}

function Get-ProcessTopLevelWindows {
    # Returns EVERY top-level window owned by $ProcessId (visible or not), not just the
    # single Z-order-topmost one .NET's Process class exposes. Safe to call for a dead/
    # missing PID - EnumWindows simply yields zero matches, no exception.
    param(
        [Parameter(Mandatory)][int]$ProcessId
    )
    Initialize-Win32WindowEnum
    $results = [System.Collections.Generic.List[object]]::new()
    $callback = {
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        $wpid = 0
        [void][ClaudeConnectWin32Window]::GetWindowThreadProcessId($hWnd, [ref]$wpid)
        if ($wpid -eq $ProcessId) {
            $title = ''
            $len = [ClaudeConnectWin32Window]::GetWindowTextLength($hWnd)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][ClaudeConnectWin32Window]::GetWindowText($hWnd, $sb, $sb.Capacity)
                $title = $sb.ToString()
            }
            $visible = [bool]([ClaudeConnectWin32Window]::IsWindowVisible($hWnd))
            $results.Add([PSCustomObject]@{ Hwnd = $hWnd; Title = $title; Visible = $visible })
        }
        return $true
    }
    try {
        [void][ClaudeConnectWin32Window]::EnumWindows($callback, [IntPtr]::Zero)
    } catch {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "WIN32_ENUM_WINDOWS_FAIL: pid=$ProcessId error=$($_.Exception.Message)" 'WARN'
        }
    }
    return @($results)
}

# Bug 10 fix (2026-07-24, live repro): Cursor is launched via a background Scheduled Task
# ("LIMITED" task, commit b394340) or a detached process, neither of which is the current
# foreground app, so Windows' anti focus-stealing protection denies the new/detected window
# SetForegroundWindow rights by default - the window opens but stays behind other windows or
# minimized in the taskbar, and the user has to manually alt-tab to find it. A plain
# SetForegroundWindow call from a background PowerShell process is silently ignored by Windows
# for the same reason. The standard, documented workaround (AttachThreadInput) temporarily
# attaches our calling thread's input queue to whichever thread currently owns the real
# foreground window, which grants us the right to move foreground focus - this is the
# conventional technique for this exact "background process must foreground someone else's
# window" scenario (no legitimate Win32 API exists to unconditionally force foreground from a
# background process; AttachThreadInput is the sanctioned indirect route).
function Set-CursorWindowForeground {
    param([Parameter(Mandatory)][System.IntPtr]$Hwnd)
    Initialize-Win32WindowEnum
    try {
        if ([ClaudeConnectWin32Window]::IsIconic($Hwnd)) {
            [void][ClaudeConnectWin32Window]::ShowWindow($Hwnd, 9)  # SW_RESTORE
        }
        $fgHwnd = [ClaudeConnectWin32Window]::GetForegroundWindow()
        $fgPid = 0
        $fgThreadId = [ClaudeConnectWin32Window]::GetWindowThreadProcessId($fgHwnd, [ref]$fgPid)
        $targetPid = 0
        $targetThreadId = [ClaudeConnectWin32Window]::GetWindowThreadProcessId($Hwnd, [ref]$targetPid)
        $attached = $false
        if ($fgThreadId -ne 0 -and $targetThreadId -ne 0 -and $fgThreadId -ne $targetThreadId) {
            $attached = [bool][ClaudeConnectWin32Window]::AttachThreadInput($targetThreadId, $fgThreadId, $true)
        }
        try {
            $ok = [bool][ClaudeConnectWin32Window]::SetForegroundWindow($Hwnd)
        } finally {
            if ($attached) { [void][ClaudeConnectWin32Window]::AttachThreadInput($targetThreadId, $fgThreadId, $false) }
        }
        return $ok
    } catch {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "SET_FOREGROUND_FAIL: error=$($_.Exception.Message)" 'WARN'
        }
        return $false
    }
}
# #endregion

function Get-RemoteEditorProcesses {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$ForceRefresh
    )
    $exe = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $uriNeedle = "ssh-remote+${Alias}"
    $pathNeedle = $RemotePath.TrimEnd('/')
    $pathNeedleEsc = [regex]::Escape($pathNeedle)
    $profileDir = if ($EditorCmd -eq 'cursor') { Get-CursorRemoteProfileDir } elseif ($EditorCmd -eq 'code') { Get-CodeRemoteProfileDir } else { $null }

    $matches = @(Invoke-CimEditorProcessQuery -ExeName $exe -Reason 'remote_editor_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $cmd = $_.CommandLine
            if (-not $cmd) { return $false }
            if (-not (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedleEsc)) { return $false }
            if ($cmd -match [regex]::Escape($uriNeedle)) { return $true }
            if ($profileDir -and ($cmd -match [regex]::Escape($profileDir))) { return $true }
            return $false
        })
    return $matches
}

function Test-RemoteEditorWindowOpen {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Auth gate: on correct folder AND a visible process with uri/path match.
    if (-not (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        return $false
    }
    return (Test-RemoteEditorWindowOpenWhenOnFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
}

function Test-CursorVisibleWindowMatchesProject {
    # True only when a VISIBLE top-level window title matches THIS project root.
    # Cmdline folder-uri alone is not enough (shared profile PID keeps stale URIs while
    # showing Agents / another project - live known_on_folder false skip 2026-07-28).
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$RootName,
        [string]$TitleTag = (Get-CursorWindowTitleTag),
        [string]$AliasNeedleEscaped = ''
    )
    if (-not $RootName) { return $false }
    $wins = @()
    try {
        $wins = @(Get-ProcessTopLevelWindows -ProcessId $ProcessId | Where-Object { $_.Visible -and $_.Title })
    } catch { return $false }
    foreach ($win in $wins) {
        if (Test-CursorWindowTitleMatchesProject -Title $win.Title -RootName $RootName -TitleTag $TitleTag -AliasNeedleEscaped $AliasNeedleEscaped) {
            return $true
        }
    }
    return $false
}

function Test-RemoteEditorWindowOpenWhenOnFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Project-scoped only. Never treat cmdline+any-MainWindowHandle as open (shared profile
    # PID keeps stale folder-uri while another window is Z-top - deep-review 2026-07-28).
    if ($EditorCmd -eq 'cursor') {
        $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1]
        $titleTag = Get-CursorWindowTitleTag
        $aliasOnlyNeedle = [regex]::Escape($Alias)
        foreach ($p in @(Get-CursorMainProfileProcesses)) {
            $wins = @()
            try {
                $wins = @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId | Where-Object { $_.Visible -and $_.Title })
            } catch { $wins = @() }
            foreach ($win in $wins) {
                if (-not (Test-CursorWindowTitleMatchesProject -Title $win.Title -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle)) {
                    continue
                }
                Request-CursorWindowForegroundOnce -RemotePath $RemotePath -Hwnd $win.Hwnd
                return $true
            }
        }
        return $false
    }
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                Request-CursorWindowForegroundOnce -RemotePath $RemotePath -Hwnd $wp.MainWindowHandle
                return $true
            }
        } catch {}
    }
    return $false
}

# Bug 10 fix: foreground the confirmed-open window exactly once per RemotePath (not on every
# poll tick) - repeated SetForegroundWindow calls while the user is deliberately working in a
# different app would be its own annoyance, so only steal focus the first time this specific
# project's window is confirmed open after a launch.
function Request-CursorWindowForegroundOnce {
    param(
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][System.IntPtr]$Hwnd
    )
    if (-not $script:CursorForegroundedForPath) { $script:CursorForegroundedForPath = @{} }
    if ($script:CursorForegroundedForPath.ContainsKey($RemotePath)) { return }
    $script:CursorForegroundedForPath[$RemotePath] = $true
    $ok = Set-CursorWindowForeground -Hwnd $Hwnd
    if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
        Write-EditorLaunchLog "SET_FOREGROUND: path=$RemotePath ok=$ok" 'INFO'
    }
}

function Get-RemoteFolderUri {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $path = $RemotePath.TrimEnd('/')
    return "vscode-remote://ssh-remote+${Alias}${path}"
}

function Get-CursorMainProfileProcesses {
    param([string]$ProfileDir = (Get-CursorRemoteProfileDir))
    # Callers MUST @()-wrap before `.Count`: PowerShell unwraps a single-element
    # `return @(...)` to a bare object, so bare `.Count` is $null and one live main
    # looks like "no main" (orphan_helpers) -> LAUNCH_REAP kills the open Cursor window
    # (hit live 20260803.5). Do not use Write-Output -NoEnumerate here - it breaks
    # `@($result).Count` / foreach for multi-process trees.
    return @(Get-CursorProfileProcesses -ProfileDir $ProfileDir |
        Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') })
}

function Get-CursorMainPersonalProcesses {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [switch]$ForceRefresh
    )
    if (-not $ProfileDir) { return @() }
    $profileEsc = [regex]::Escape($ProfileDir)
    return @(Invoke-CimCursorProcessQuery -Reason 'personal_procs' -ForceRefresh:$ForceRefresh |
        Where-Object {
            $_.CommandLine -and ($_.CommandLine -notmatch $profileEsc) -and ($_.CommandLine -notmatch '--type=')
        })
}

function Test-PersonalCursorDominant {
    $personalMain = @(Get-CursorMainPersonalProcesses).Count
    $profileMain = @(Get-CursorMainProfileProcesses).Count
    return ($personalMain -ge 3 -and $profileMain -eq 0)
}

function Test-CursorWindowTitleIsAgentHome {
    param(
        [string]$Title,
        [string]$ProjectRootName = ''
    )
    if (-not $Title) { return $false }
    # If the title shows THIS project at the template-anchored position, it is a real project window,
    # not the agent-home splash. Use the anchored matcher (not a bare substring) so the "Smart" site
    # tag / prefix siblings do not spoof a project match.
    if ($ProjectRootName -and (Test-CursorWindowTitleMatchesProject -Title $Title -RootName $ProjectRootName)) {
        return $false
    }
    if ($Title -match '(?i)^cursor agents$|cursor agents\b|agent home') { return $true }
    return $false
}

function Test-CursorWindowShowsAgentHome {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$RemotePath = ''
    )
    $rootName = ''
    if ($RemotePath) { $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1] }
    try {
        $wp = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        return (Test-CursorWindowTitleIsAgentHome -Title $wp.MainWindowTitle -ProjectRootName $rootName)
    } catch { }
    return $false
}

function Test-RemoteEditorOnCorrectFolder {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    if ($EditorCmd -ne 'cursor') {
        return (Test-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -gt 0
    }
    # NOTE: intentionally NO global "if (Test-RemoteEditorInAgentHome) return false" short-circuit here.
    # A standalone "Cursor Agents" window is normal in Cursor 3.x and coexists with real project windows;
    # the old global veto made on_folder=false for EVERY project whenever any agent-home window existed,
    # which blocked launch success and triggered the "drifted to Agent/home" relaunch loop even though the
    # project WAS open. Per-window agent-home is still checked below (only a window that BOTH matches this
    # project AND is itself on agent-home is rejected), which is the correct, project-scoped test.
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $pathNeedle = [regex]::Escape($RemotePath.TrimEnd('/'))
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($RemotePath.TrimEnd('/') -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $titleTag = Get-CursorWindowTitleTag
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        $cmd = $p.CommandLine
        # Cmdline may still name an old folder-uri while the only visible window is Agents
        # or another project (one shared profile PID). Require a title-matched VISIBLE window.
        if ($cmd) {
            $cmdClaimsFolder = $false
            if (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $uriNeedle) { $cmdClaimsFolder = $true }
            elseif ($cmd -match $aliasNeedle -and (Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)) { $cmdClaimsFolder = $true }
            if ($cmdClaimsFolder) {
                if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                    if (Test-CursorVisibleWindowMatchesProject -ProcessId $p.ProcessId -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle) {
                        return $true
                    }
                }
                continue
            }
        }
        if ($rootNeedle) {
            # H11_multi_window_enum: MainWindowTitle alone is the Z-order-topmost window of
            # this PID ONLY - when another project's window is already open+focused on this
            # shared profile process, MainWindowTitle keeps returning THAT window's title
            # forever and this check would never see a genuinely-opened window for a
            # different project hosted in the very same process. Enumerate every top-level
            # window actually owned by the PID and apply the exact same title-match rule to
            # each one. Require Visible so we do not skip launch for a zombie/invisible title.
            if (Test-CursorVisibleWindowMatchesProject -ProcessId $p.ProcessId -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle) {
                return $true
            }
        }
    }
    return $false
}

function Get-RemoteEditorSessionPresence {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Bug 60: single-pass on_folder + window_open (one CIM walk via shared cache).
    $onFolder = $false
    $windowOpen = $false
    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $onFolder = ($matched.Count -gt 0)
        foreach ($p in $matched) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
            } catch { }
        }
        return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
    }
    # OnFolder MUST match Test-RemoteEditorOnCorrectFolder (multi-window title enum). The old
    # version short-circuited on Test-RemoteEditorInAgentHome (standalone Agents window poisoned
    # every project) AND only inspected MainWindowTitle (Z-order-topmost of the shared PID), so
    # when refactoreoldclub was focused and dakhl was open in a second window of the SAME process,
    # presence.OnFolder stayed False forever even though on_folder=True - connect status showed
    # "agent" / "Opening Cursor failed" while the project window was visibly open (live 2026-07-25).
    $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        foreach ($win in @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId)) {
            if ($win.Title) { $windowOpen = $true; break }
        }
        if ($windowOpen) { break }
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $windowOpen = $true; break }
        } catch { }
    }
    return [pscustomobject]@{ OnFolder = [bool]$onFolder; WindowOpen = [bool]$windowOpen }
}

function Get-RemoteEditorStateExplain {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $bits = @()
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $path = $RemotePath.TrimEnd('/')
    $bits += "target_uri=$uri target_path=$path"

    if ($EditorCmd -ne 'cursor') {
        $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
        $bits += "editor=$EditorCmd matched_procs=$($matched.Count) on_folder=$($matched.Count -gt 0)"
        return ($bits -join ' | ')
    }

    $profileDir = Get-CursorRemoteProfileDir
    $mains = @(Get-CursorMainProfileProcesses)
    $allProfile = @(Get-CursorProfileProcesses)
    $allCursor = @(Invoke-CimCursorProcessQuery -Reason 'state_explain_all')
    $personalCount = @($allCursor | Where-Object {
        $_.CommandLine -and ($_.CommandLine -notmatch [regex]::Escape($profileDir))
    }).Count
    $bits += "cursor_total=$($allCursor.Count) profile_total=$($allProfile.Count) profile_main=$($mains.Count) personal_main=$personalCount"

    $agentHome = Test-RemoteEditorInAgentHome -RemotePath $RemotePath
    $bits += "agent_home=$agentHome"
    if ($agentHome) {
        foreach ($p in $mains) {
            $cmd = $p.CommandLine
            if (-not $cmd) {
                $bits += "agent_reason pid=$($p.ProcessId) empty_cmdline"
                continue
            }
            if ($cmd -notmatch 'folder-uri') {
                $bits += "agent_reason pid=$($p.ProcessId) no_folder_uri_in_cmd"
            } elseif (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) {
                $bits += "agent_reason pid=$($p.ProcessId) folder_uri_ignored_title_agents"
            }
        }
    }

    $pathNeedle = [regex]::Escape($path)
    $aliasNeedle = [regex]::Escape("ssh-remote+${Alias}")
    $uriNeedle = [regex]::Escape($uri)
    $rootName = ($path -split '/')[-1]
    $rootNeedle = if ($rootName) { [regex]::Escape($rootName) } else { '' }
    $titleTag = Get-CursorWindowTitleTag
    $aliasOnlyNeedle = [regex]::Escape($Alias)
    $onFolder = $false
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) {
            $bits += "main pid=$($p.ProcessId) empty_cmdline"
            continue
        }
        $uriHit = Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $uriNeedle
        $rawAliasMatch = [bool]($cmd -match $aliasNeedle)
        $boundaryPathMatch = [bool](Test-PathNeedleBoundaryMatch -CommandLine $cmd -NeedleEscaped $pathNeedle)
        $aliasPathHit = $rawAliasMatch -and $boundaryPathMatch
        $titleHit = $false
        $title = ''
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            $title = $wp.MainWindowTitle
            if ($rootNeedle -and (Test-CursorWindowTitleMatchesProject -Title $title -RootName $rootName -TitleTag $titleTag -AliasNeedleEscaped $aliasOnlyNeedle)) {
                $titleHit = $true
            }
        } catch { }
        $bits += (
            "main pid=$($p.ProcessId) uri_hit=$uriHit alias_path_hit=$aliasPathHit title_hit=$titleHit " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd -MaxLen 180)"
        )
        if ($uriHit -or $aliasPathHit) {
            if (-not (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath)) {
                $onFolder = $true
            }
        }
        if ($titleHit) { $onFolder = $true }
    }
    if ($mains.Count -eq 0) {
        $bits += 'folder_reason=no_profile_main_process'
    } elseif (-not $onFolder) {
        $bits += 'folder_reason=no_main_process_matched_uri_alias_or_title'
    }
    $bits += "on_folder=$onFolder window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    return ($bits -join ' | ')
}

function Write-EditorLaunchVerboseState {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$IncludeSnapshot,
        [switch]$ForceLog
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $alwaysLog = $ForceLog -or $Label -match '^EXHAUSTED' -or $script:VerboseLaunch
    if (-not $alwaysLog) {
        $sw.Stop()
        Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra 'skipped=gated'
        return
    }
    Write-EditorLaunchLog "STATE[$Label] $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DIAG[$Label] $(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    Write-EditorLaunchLog "DETECT[$Label] $(Get-RemoteEditorDetectionDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
    if ($EditorCmd -eq 'cursor') {
        Write-EditorLaunchLog "STORAGE[$Label] $(Get-CursorProfileStorageDiag)" 'DEBUG'
    }
    if ($IncludeSnapshot -and ($script:VerboseLaunch -or $ForceLog)) {
        Write-EditorLaunchSnapshot -Label $Label -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    }
    $sw.Stop()
    Write-LaunchPerfLog -Mark "verbose_$Label" -Ms $sw.ElapsedMilliseconds -Extra "snapshot=$([bool]$IncludeSnapshot)"
}

function Test-RemoteEditorInAgentHome {
    param(
        [string]$ProfileDir = (Get-CursorRemoteProfileDir),
        [string]$RemotePath = ''
    )
    foreach ($p in @(Get-CursorMainProfileProcesses -ProfileDir $ProfileDir)) {
        $cmd = $p.CommandLine
        if (-not $cmd) { continue }
        # Agent/home title wins even when folder-uri is present (Cursor 3.x forum #153009).
        if (Test-CursorWindowShowsAgentHome -ProcessId $p.ProcessId -RemotePath $RemotePath) { return $true }
        # A main process opens a folder via EITHER --folder-uri=... OR --remote ssh-remote+<alias> <path>
        # (equivalently a vscode-remote:// uri). The cmd-line fallback below must only flag agent-home
        # when the launch opened NO folder at all - otherwise the --remote-first strategy (the reliable
        # warm-handoff path) is misread as agent-home on EVERY poll, and the success gate (-not agent_home)
        # rejects every launch even though the window actually opened. Live regression 2026-07-25: after
        # reordering strategies to --remote first, project windows never "succeeded" (agent_home=True stuck).
        $opensFolder = ($cmd -match 'folder-uri') -or ($cmd -match '(?i)(^|\s)--remote(\s|=)') -or ($cmd -match 'ssh-remote\+') -or ($cmd -match 'vscode-remote://')
        if (-not $opensFolder) {
            $title = ''
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = [string]$wp.MainWindowTitle
            } catch { }
            # Settings (and similar) often lack a folder - do not treat as agent-home.
            if ($title -match '(?i)settings') { continue }
            return $true
        }
    }
    return $false
}

function Write-EditorLaunchLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog $Message $Level
    }
}

function Get-CursorProfileStorageDiag {
    $profileDir = Get-CursorRemoteProfileDir
    $gs = Join-Path $profileDir 'User\globalStorage'
    $ws = Join-Path $profileDir 'User\workspaceStorage'
    $db = Join-Path $gs 'state.vscdb'
    $storageJson = Join-Path $gs 'storage.json'
    $wsCount = 0
    if (Test-Path $ws) { $wsCount = @(Get-ChildItem -Path $ws -Directory -ErrorAction SilentlyContinue).Count }
    $dbSize = if (Test-Path $db) { (Get-Item $db).Length } else { 0 }
    $walSize = if (Test-Path "$db-wal") { (Get-Item "$db-wal").Length } else { 0 }
    $recent = ''
    if (Test-Path $storageJson) {
        try {
            $sj = Get-Content $storageJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($sj.'telemetry.machineId') { $recent += " machineId=set" }
        } catch { $recent = 'storage_json_read_error' }
    }
    return (
        "profile_dir=$profileDir globalStorage_exists=$(Test-Path $gs) state_vscdb=$dbSize wal=$walSize " +
        "workspaceStorage_dirs=$wsCount$recent"
    )
}

function Get-ForegroundWindowTitle {
    try {
        if (-not ('Win32.ForegroundWindow' -as [type])) {
            Add-Type -Name ForegroundWindow -Namespace Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
'@ -ErrorAction Stop
        }
        $hwnd = [Win32.ForegroundWindow]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return '' }
        $sb = New-Object System.Text.StringBuilder 512
        [void][Win32.ForegroundWindow]::GetWindowText($hwnd, $sb, $sb.Capacity)
        return $sb.ToString()
    } catch {
        return ''
    }
}

function Get-RemoteEditorLaunchDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
    $foregroundTitle = Get-ForegroundWindowTitle
    $mains = if ($EditorCmd -eq 'cursor') { @(Get-CursorMainProfileProcesses) } else { @() }
    $mainSummaries = @()
    foreach ($p in $mains) {
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $hasUri = $cmd -match 'folder-uri'
        $hasRemote = $cmd -match '--remote'
        $hasClassic = $cmd -match '--classic'
        $hasPath = $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))
        if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '...' }
        $mainSummaries += "pid=$($p.ProcessId) uri=$hasUri remote=$hasRemote classic=$hasClassic path=$hasPath cmd=$cmd"
    }
    $mainText = if ($mainSummaries.Count -gt 0) { ($mainSummaries -join ' | ') } else { 'none' }
    return (
        "expected_uri=$uri on_folder=$onFolder agent_home=$agentHome window_open=$windowOpen " +
        "foreground_title=$foregroundTitle main_count=$($mains.Count) main=[$mainText]"
    )
}


function Get-CursorProxyLaunchArgs {
    # Chromium/Electron flags: settings.json alone is not enough on Cursor 3.9.x
    # Prefer sticky sidecar front door (18999) when listening AND backend -L is up.
    # Last resort: no --proxy-server (server_direct / none_direct) so Cursor is not
    # stuck on a dead 18998/18999 loopback proxy.
    $port = 0
    $mode = 'none_direct'
    $front = 0
    if ($script:CursorSocksFrontPort) { $front = [int]$script:CursorSocksFrontPort }
    $frontUp = $false
    if ($front -gt 0) {
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-LocalPortOpen -PortNum $front)
        } elseif (Get-Command Test-CursorProxySidecarListening -ErrorAction SilentlyContinue) {
            $frontUp = [bool](Test-CursorProxySidecarListening -Port $front)
        }
    }
    $backSocks = 0
    if ($script:SocksProxyPort) { $backSocks = [int]$script:SocksProxyPort }
    $backUp = $false
    if ($backSocks -gt 0) {
        if (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue) {
            $backUp = [bool](Test-LocalPortOpen -PortNum $backSocks)
        } else {
            $backUp = $true
        }
    }
    if ($frontUp -and $front -gt 0 -and $backUp) {
        $port = $front
        $mode = 'sidecar'
    } elseif ($backUp -and $backSocks -gt 0) {
        $port = $backSocks
        $mode = 'xray'
    }
    if ($port -le 0) {
        if (Get-Command Get-CursorProxyMode -ErrorAction SilentlyContinue) {
            try { $mode = Get-CursorProxyMode } catch { $mode = 'server_direct' }
        } else {
            $mode = 'server_direct'
        }
        if ($mode -ne 'server_direct' -and $mode -ne 'none_direct') { $mode = 'server_direct' }
        Write-EditorLaunchLog ("LAUNCH_PROXY mode={0}" -f $mode) 'INFO'
        return @()
    }
    Write-EditorLaunchLog ("LAUNCH_PROXY mode={0} socks={1}" -f $mode, $port) 'INFO'
    return @(
        "--proxy-server=socks5://127.0.0.1:$port",
        '--disable-http2'
    )
}

function Get-RemoteEditorLaunchStrategies {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Uri,
        [switch]$NewWindow,
        # When the shared profile already has windows open, try --remote then one --remote-classic
        # fallback. Live 2026-07-25: cascading to folder-uri / folder-uri-classic within ~5s of the
        # first --remote IPC handoff interrupts Cursor mid-connect (Welcome trap; forum #153009).
        # P0.4 (2026-08-02): a single all-or-nothing warm strategy left no recovery when --remote
        # alone did not settle on_folder - remote-classic is a safe sibling (same --remote IPC,
        # not folder-uri). Still avoid folder-uri on warm.
        [switch]$WarmHandoff
    )
    $path = $RemotePath.TrimEnd('/')
    $remoteArg = "ssh-remote+${Alias}"
    $strategies = @()

    # Strategy ORDER matters. Live-verified 2026-07-25 (Cursor 3.x, Windows, warm instance):
    #
    #   --remote ssh-remote+<alias> <path>      -> opens the REAL folder in a new window, both
    #                                              cold AND when Cursor is already running (warm
    #                                              IPC handoff). Confirmed via screenshot: a fresh
    #                                              window loaded "<PROJECT> [SSH: <alias>]" in the
    #                                              explorer, not the Welcome/Agents splash.
    #   --folder-uri=vscode-remote://ssh-remote+.../<path>  -> works when Cursor is CLOSED, but on
    #                                              a warm handoff Cursor lands on the Welcome/Agents
    #                                              page and NEVER opens the folder (Cursor forum
    #                                              #153009, #165329; microsoft/vscode #209072). The
    #                                              '=' form survives Chromium's '://' arg filter but
    #                                              does NOT fix the warm-handoff welcome-page bug.
    #
    # So --remote MUST come first. It was previously last, behind folder-uri-classic/folder-uri,
    # so every warm launch (picking a 2nd/3rd project while a window is open) opened Welcome and
    # the real folder never loaded (project "smart"/"deploy" "did not open" reports 2026-07-25).
    # folder-uri variants are kept only as cold-start fallbacks. --classic is not needed for the
    # folder to open (the verified working invocation had no --classic) and is demoted to fallback.
    #
    # Order decision 2026-08-02 (Cursor 3.13.10, one cold session): folder-uri-classic eventually
    # won after remote/remote-classic/folder-uri exhausted a short 3s/strategy budget. That does
    # NOT overturn --remote-first: (1) warm evidence for --remote is deliberate and screenshot-
    # verified; (2) premature cold cascade was a poll-budget bug (3s << cold boot), not proof
    # folder-uri-classic should lead; (3) putting folder-uri earlier would re-arm the warm Welcome
    # trap. Keep --remote first; give cold attempt-1 a longer poll instead of reordering.
    $folderUriArg = "--folder-uri=$Uri"

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $common = @('--user-data-dir', $profileDir)
        $common += @(Get-CursorProxyLaunchArgs)
        if ($NewWindow) { $common += '--new-window' }
        $strategies += [PSCustomObject]@{
            Name = 'remote'
            Args = $common + @('--remote', $remoteArg, $path)
        }
        if ($WarmHandoff) {
            # remote + remote-classic only. Do NOT cascade folder-uri (Welcome / IPC interrupt).
            $strategies += [PSCustomObject]@{
                Name = 'remote-classic'
                Args = $common + @('--classic', '--remote', $remoteArg, $path)
            }
            return $strategies
        }
        $strategies += [PSCustomObject]@{
            Name = 'remote-classic'
            Args = $common + @('--classic', '--remote', $remoteArg, $path)
        }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri'
            Args = $common + @($folderUriArg)
        }
        $strategies += [PSCustomObject]@{
            Name = 'folder-uri-classic'
            Args = $common + @('--classic', $folderUriArg)
        }
        return $strategies
    }

    $profileDir = Get-CodeRemoteProfileDir
    $common = @('--user-data-dir', $profileDir)
    if ($NewWindow) { $common += '--new-window' }
    # --remote first (see cursor branch above): it opens the real folder on a warm handoff,
    # whereas --folder-uri lands on Welcome when the editor is already running.
    $strategies += [PSCustomObject]@{
        Name = 'remote'
        Args = $common + @('--remote', $remoteArg, $path)
    }
    $strategies += [PSCustomObject]@{
        Name = 'folder-uri'
        Args = $common + @($folderUriArg)
    }
    return $strategies
}

function Format-EditorProcessCommandLine {
    param(
        [string]$CommandLine,
        [int]$MaxLen = 220
    )
    if (-not $CommandLine) { return '' }
    if ($CommandLine.Length -le $MaxLen) { return $CommandLine }
    return $CommandLine.Substring(0, $MaxLen) + '...'
}

function Get-RemoteEditorProcessSnapshot {
    param(
        [string]$EditorCmd = 'cursor',
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    $lines = @()
    $lines += "snapshot_ts=$(Get-Date -Format 'o')"
    $lines += "elevated=$(Test-IsElevatedShell) interactive_user=$(Get-InteractiveWindowsUser)"
    if ($Alias -and $RemotePath) {
        $lines += "target_alias=$Alias target_path=$RemotePath target_uri=$(Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath)"
        $lines += "detect_on_folder=$(Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        if ($EditorCmd -eq 'cursor') {
            $lines += "detect_agent_home=$(Test-RemoteEditorInAgentHome -RemotePath $RemotePath)"
        }
        $lines += "detect_window_open=$(Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
    }

    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $lines += "profile_dir=$profileDir profile_exists=$(Test-Path $profileDir)"
        $settingsPath = Join-Path $profileDir 'User\settings.json'
        $lines += "profile_settings_exists=$(Test-Path $settingsPath)"
        $lines += (Get-CursorProfileStorageDiag)
    }

    $exeName = if ($EditorCmd -eq 'cursor') { 'Cursor.exe' } else { 'Code.exe' }
    $all = @(Invoke-CimEditorProcessQuery -ExeName $exeName -Reason 'process_snapshot')
    $lines += "${exeName}_total=$($all.Count)"
    if ($EditorCmd -eq 'cursor') {
        $profileDir = Get-CursorRemoteProfileDir
        $profileCount = @($all | Where-Object { $_.CommandLine -and ($_.CommandLine -match [regex]::Escape($profileDir)) }).Count
        $personalCount = $all.Count - $profileCount
        $lines += "cursor_profile_procs=$profileCount cursor_personal_procs=$personalCount"
    }

    $idx = 0
    foreach ($p in $all) {
        $idx++
        $cmd = $p.CommandLine
        if (-not $cmd) { $cmd = '' }
        $procType = 'unknown'
        if ($cmd -match '--type=renderer') { $procType = 'renderer' }
        elseif ($cmd -match '--type=gpu-process') { $procType = 'gpu' }
        elseif ($cmd -match '--type=utility') { $procType = 'utility' }
        elseif ($cmd -notmatch '--type=') { $procType = 'main' }
        $isMain = ($procType -eq 'main')
        $isProfile = $false
        $hasFolderUri = $false
        $hasRemote = $false
        $hasClassic = $false
        $hasNewWindow = $false
        $hasUserData = $false
        $pathMatch = $false
        $aliasMatch = $false
        if ($EditorCmd -eq 'cursor') {
            $profileDir = Get-CursorRemoteProfileDir
            if ($profileDir -and $cmd -match [regex]::Escape($profileDir)) { $isProfile = $true }
        }
        if ($cmd -match '--folder-uri') { $hasFolderUri = $true }
        if ($cmd -match '--remote') { $hasRemote = $true }
        if ($cmd -match '--classic') { $hasClassic = $true }
        if ($cmd -match '--new-window') { $hasNewWindow = $true }
        if ($cmd -match '--user-data-dir') { $hasUserData = $true }
        if ($RemotePath -and $cmd -match [regex]::Escape($RemotePath.TrimEnd('/'))) { $pathMatch = $true }
        if ($Alias -and $cmd -match [regex]::Escape("ssh-remote+${Alias}")) { $aliasMatch = $true }
        $title = ''
        $hwnd = 0
        if ($isMain) {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                $title = $wp.MainWindowTitle
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = 1 }
            } catch { }
        }
        $lines += (
            "${exeName}#$idx pid=$($p.ProcessId) parent=$($p.ParentProcessId) type=$procType main=$isMain profile=$isProfile hwnd=$hwnd " +
            "folder_uri=$hasFolderUri remote=$hasRemote classic=$hasClassic new_window=$hasNewWindow " +
            "user_data=$hasUserData alias_match=$aliasMatch path_match=$pathMatch " +
            "title=$title cmd=$(Format-EditorProcessCommandLine -CommandLine $cmd)"
        )
    }
    return ($lines -join ' | ')
}

function Write-EditorLaunchSnapshot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$EditorCmd,
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    Write-EditorLaunchLog "SNAPSHOT[$Label] $(Get-RemoteEditorProcessSnapshot -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
}

function Get-RemoteEditorDetectionDiag {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $matched = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    $visible = 0
    $hwndZero = 0
    foreach ($p in $matched) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $visible++ } else { $hwndZero++ }
        } catch { $hwndZero++ }
    }
    $profileCount = 0
    $profileVisible = 0
    if ($EditorCmd -eq 'cursor') {
        foreach ($p in @(Get-CursorProfileProcesses)) {
            $profileCount++
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
                if ($wp.MainWindowHandle -ne [IntPtr]::Zero) { $profileVisible++ }
            } catch { }
        }
    }
    $pathTail = $RemotePath.TrimEnd('/')
    if ($pathTail.Length -gt 48) { $pathTail = '...' + $pathTail.Substring($pathTail.Length - 45) }
    return (
        "matched=$($matched.Count) visible=$visible hwnd0=$hwndZero " +
        "profile=$profileCount profile_visible=$profileVisible path=$pathTail"
    )
}

function Stop-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath
    )
    # Path/alias scoped only - never kills the whole ClaudeServerCursorProfile tree.
    $procs = @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)
    Write-EditorLaunchLog (
        "STOP_REMOTE_EDITOR: path_scoped_only alias=$Alias path=$RemotePath matched=$($procs.Count)"
    ) 'INFO'
    if ($procs.Count -eq 0) {
        Write-EditorLaunchLog 'STOP_REMOTE_EDITOR: no matching processes' 'DEBUG'
        return
    }

    foreach ($p in $procs) {
        try {
            $wp = [System.Diagnostics.Process]::GetProcessById($p.ProcessId)
            if ($wp.MainWindowHandle -ne [IntPtr]::Zero) {
                $null = $wp.CloseMainWindow()
            }
        } catch { }
    }
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath).Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 500
    }
    foreach ($p in @(Get-RemoteEditorProcesses -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-Win32WindowClose {
    if ($script:Win32WindowCloseReady) { return }
    if (-not ('ClaudeConnectWin32Close' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClaudeConnectWin32Close
{
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public const uint WM_CLOSE = 0x0010;
}
'@ -ErrorAction Stop
    }
    $script:Win32WindowCloseReady = $true
}

function Close-CursorProjectWindows {
    # Window-scoped close for ONE project root. Never Stop-CursorServerProfileTree.
    # Never closes personal Cursor. Skips windows matching ProtectRootName (current session).
    param(
        [Parameter(Mandatory)][string]$ProjectRootName,
        [string]$ProtectRootName = '',
        [string]$Alias = 'claude-server'
    )
    $root = ($ProjectRootName + '').Trim()
    if (-not $root) { return 0 }
    $protect = ($ProtectRootName + '').Trim()
    if ($protect -and ($protect -ieq $root)) {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "CLOSE_CURSOR_PROJECT_WINDOW: skip root=$root reason=equals_protect" 'WARN'
        }
        return 0
    }
    Initialize-Win32WindowClose
    $titleTag = Get-CursorWindowTitleTag
    $aliasEsc = [regex]::Escape(($Alias + '').Trim())
    $closed = 0
    $protectStillOpen = $false
    foreach ($p in @(Get-CursorMainProfileProcesses)) {
        foreach ($win in @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId)) {
            $title = [string]$win.Title
            if (-not $title) { continue }
            if ($protect -and (Test-CursorWindowTitleMatchesProject -Title $title -RootName $protect -TitleTag $titleTag -AliasNeedleEscaped $aliasEsc)) {
                $protectStillOpen = $true
                continue
            }
            if (-not (Test-CursorWindowTitleMatchesProject -Title $title -RootName $root -TitleTag $titleTag -AliasNeedleEscaped $aliasEsc)) {
                continue
            }
            try {
                [void][ClaudeConnectWin32Close]::PostMessage([IntPtr]$win.Hwnd, [ClaudeConnectWin32Close]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
                $closed++
                if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                    Write-EditorLaunchLog ("CLOSE_CURSOR_PROJECT_WINDOW: hwnd={0} root={1} title={2}" -f $win.Hwnd, $root, $title) 'INFO'
                }
            } catch {
                if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                    Write-EditorLaunchLog ("CLOSE_CURSOR_PROJECT_WINDOW_FAIL: root={0} err={1}" -f $root, $_.Exception.Message) 'WARN'
                }
            }
        }
    }
    if ($closed -eq 0 -and $protectStillOpen) {
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog "CLOSE_CURSOR_PROJECT_WINDOW: no_match root=$root protect_open=1 (shared profile; skipped process kill)" 'WARN'
        }
    }
    return $closed
}

function Get-CursorLaunchWindowPlan {
    # profile_all>0 with profile_main=False ("orphan helpers") means helpers from a
    # half-dead profile OR a sibling window still spinning up. Caller settles then
    # reaps helpers-only (Stop-CursorServerProfileTree â†’ cold). Do NOT request
    # --new-window for orphanHelpers alone â€” that amplified litter (amir V19).
    # UseNewWindow = AgentHome OR HasProfileWindow ONLY.
    param(
        [Parameter(Mandatory)][bool]$AgentHome,
        [Parameter(Mandatory)][bool]$HasProfileWindow,
        [Parameter(Mandatory)][int]$ProfileProcCount
    )
    $orphanHelpers = ((-not $HasProfileWindow) -and ($ProfileProcCount -gt 0))
    $useNewWindow = ($AgentHome -or $HasProfileWindow)
    $reason = if ($AgentHome) { 'agent_home' } elseif ($HasProfileWindow) { 'profile_open' } elseif ($orphanHelpers) { 'orphan_helpers' } else { 'cold_start' }
    return [pscustomobject]@{ UseNewWindow = $useNewWindow; Reason = $reason; OrphanHelpers = $orphanHelpers }
}

function Enter-CursorProfileLaunchGate {
    # Serialize ClaudeServerCursorProfile launches across parallel Connect UIs.
    # Fleet 2026-08-03: W1+W2 both saw cold_start profile_all=0 and dual-spawned without
    # --new-window. Holder starts first; waiter re-queries and typically becomes profile_open.
    param([int]$TimeoutMs = 45000)
    $result = [pscustomobject]@{
        Acquired  = $false
        WaitedMs  = 0
        Contended = $false
        Mutex     = $null
    }
    try {
        $created = $false
        $mtx = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnectCursorLaunch', [ref]$created)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $got = $false
        try {
            $got = $mtx.WaitOne($TimeoutMs)
        } catch [System.Threading.AbandonedMutexException] {
            $got = $true
        } catch {
            $got = $false
        }
        $sw.Stop()
        $result.WaitedMs = [int]$sw.ElapsedMilliseconds
        if ($got) {
            $result.Acquired = $true
            $result.Mutex = $mtx
            if ($result.WaitedMs -gt 0) { $result.Contended = $true }
            if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                Write-EditorLaunchLog ("LAUNCH_GATE acquired waited_ms={0} created={1}" -f $result.WaitedMs, [int]$created) 'INFO'
            }
        } else {
            $result.Contended = $true
            try { $mtx.Dispose() } catch { }
            if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
                Write-EditorLaunchLog ("LAUNCH_GATE timeout waited_ms={0} (proceed without serialize)" -f $result.WaitedMs) 'WARN'
            }
        }
    } catch {
        $result.Contended = $true
        if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
            Write-EditorLaunchLog ("LAUNCH_GATE fail err={0}" -f $_.Exception.Message) 'WARN'
        }
    }
    return $result
}

function Exit-CursorProfileLaunchGate {
    param($Gate)
    if (-not $Gate -or -not $Gate.Acquired -or -not $Gate.Mutex) { return }
    try {
        $Gate.Mutex.ReleaseMutex()
    } catch { }
    try { $Gate.Mutex.Dispose() } catch { }
    try { $Gate.Acquired = $false } catch { }
    if (Get-Command Write-EditorLaunchLog -ErrorAction SilentlyContinue) {
        Write-EditorLaunchLog 'LAUNCH_GATE released' 'DEBUG'
    }
}

function Launch-RemoteEditor {
    param(
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$RemotePath,
        [switch]$KnownOnFolder,
        [switch]$AuthRelaunch
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("LAUNCH begin editor={0} path={1}" -f $EditorCmd, $RemotePath)
    }

    $script:LaunchCimCallCount = 0
    Clear-CursorProcessCache
    $script:LaunchPerfSw = [System.Diagnostics.Stopwatch]::StartNew()
    $fixes = if ($script:LaunchPerfFixes) { ($script:LaunchPerfFixes -join ',') } else { 'F1,F2,F3,F5,F4' }
    Write-EditorLaunchLog "LAUNCH_PERF_BEGIN fixes=$fixes" 'DEBUG'

    $cli = Get-EditorNativeExe $EditorCmd
    if (-not $cli) {
        Write-EditorLaunchLog 'LAUNCH: editor executable not found' 'ERROR'
        return $false
    }

    $uri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath

    if ($EditorCmd -eq 'cursor') {
        # Must run before Set-CursorProxySettings: it only writes the title/color template
        # when settings.json doesn't exist yet, so on a brand-new profile the proxy merge
        # below would otherwise create a proxy-only file first and permanently skip the template.
        Initialize-CursorServerProfile
        try { [void](Ensure-CursorRemoteSshQuietSettings) } catch { Write-EditorLaunchLog "CURSOR_SSH_UI_FAIL: $($_.Exception.Message)" 'WARN' }
        # Write proxy keys to disk, but NEVER soft-stop ClaudeServerCursorProfile for proxy
        # changes. Non-owners must not SET/CLEAR. Never CLEAR while profile windows are open.
        $isProxyOwner = $true
        if ($null -ne $script:CursorProxyOwner) { $isProxyOwner = [bool]$script:CursorProxyOwner }
        if (-not $isProxyOwner) {
            Write-EditorLaunchLog 'CURSOR_PROXY_SET_SKIP: reason=non_owner' 'DEBUG'
        } else {
            # Only SET when a healthy path exists (front+backend or backend). Never pin
            # settings to constant 18998/18999 when those ports are not actually usable.
            $socksForSettings = 0
            $httpForSettings = 0
            $pathHealthy = $false
            $frontSocks = 0
            $frontHttp = 0
            if ($script:CursorSocksFrontPort) { $frontSocks = [int]$script:CursorSocksFrontPort }
            if ($script:CursorHttpFrontPort) { $frontHttp = [int]$script:CursorHttpFrontPort }
            $backSocks = 0
            $backHttp = 0
            if ($script:SocksProxyPort) { $backSocks = [int]$script:SocksProxyPort }
            if ($script:HttpProxyPort) { $backHttp = [int]$script:HttpProxyPort }
            $frontUp = $false
            $backUp = $false
            if ($frontSocks -gt 0 -and $frontHttp -gt 0 -and (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) {
                $frontUp = (Test-LocalPortOpen -PortNum $frontSocks) -and (Test-LocalPortOpen -PortNum $frontHttp)
            }
            if ($backSocks -gt 0 -and $backHttp -gt 0 -and (Get-Command Test-LocalPortOpen -ErrorAction SilentlyContinue)) {
                $backUp = (Test-LocalPortOpen -PortNum $backSocks) -and (Test-LocalPortOpen -PortNum $backHttp)
            } elseif ($backSocks -gt 0 -and $backHttp -gt 0) {
                $backUp = $true
            }
            if ($frontUp -and $backUp) {
                $socksForSettings = $frontSocks
                $httpForSettings = $frontHttp
                $pathHealthy = $true
            } elseif ($backUp) {
                $socksForSettings = $backSocks
                $httpForSettings = $backHttp
                $pathHealthy = $true
            }
            if ($pathHealthy) {
                try {
                    $align = Align-CursorProxyWithRunningCli -SocksPort $socksForSettings -HttpPort $httpForSettings
                    if ($align.SocksPort) { $socksForSettings = [int]$align.SocksPort }
                    if ($align.HttpPort) { $httpForSettings = [int]$align.HttpPort }
                    $httpWrite = $httpForSettings
                    if ($httpWrite -le 0 -and $script:HttpProxyPort) { $httpWrite = [int]$script:HttpProxyPort }
                    $proxyChanged = [bool](Set-CursorProxySettings -SocksPort $socksForSettings -HttpPort $httpWrite)
                    if ($proxyChanged) {
                        Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} http={1} (no soft-stop)" -f $socksForSettings, $httpWrite) 'INFO'
                    }
                    Write-EditorLaunchLog 'LAUNCH_PROXY mode=proxy_settings_healthy' 'DEBUG'
                } catch { Write-EditorLaunchLog "CURSOR_PROXY_SET_FAIL: $($_.Exception.Message)" 'INFO' }
            } else {
                # No healthy socks/http after Ensure - clear dead 18998; last resort = direct.
                # Clear-CursorProxySettingsSidecar: CLEAR_SKIP+repair when windows open AND
                # 18998 up; FORCE clear when windows open AND 18998 down (avoid ECONNREFUSED).
                try {
                    $cleared = $false
                    $nOpen = 0
                    try { $nOpen = @(Get-CursorProfileProcesses -ForceRefresh).Count } catch { $nOpen = 0 }
                    if ($nOpen -gt 0) {
                        Write-EditorLaunchLog ("CURSOR_PROXY_CLEAR_SKIP: reason=windows_open action=repair_sidecar_only profile_count={0}" -f $nOpen) 'INFO'
                    }
                    if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                        try { $cleared = [bool](Clear-CursorProxySettingsSidecar) } catch { $cleared = $false }
                    } elseif ($nOpen -gt 0 -and (Get-Command Repair-CursorProxySettingsToSidecar -ErrorAction SilentlyContinue)) {
                        try { [void](Repair-CursorProxySettingsToSidecar) } catch {}
                    }
                    if (-not $cleared -and (Test-MayClearCursorProxySettings -AllowClear)) {
                        $proxyCleared = [bool](Clear-CursorProxySettings)
                        if ($proxyCleared) {
                            Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR: no_windows (no soft-stop)' 'INFO'
                            $cleared = $true
                        }
                    } elseif (-not $cleared) {
                        Write-EditorLaunchLog 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open_or_non_owner action=reload_for_server_direct' 'INFO'
                    }
                    Write-EditorLaunchLog 'LAUNCH_PROXY mode=server_direct' 'INFO'
                } catch { Write-EditorLaunchLog "CURSOR_PROXY_CLEAR_FAIL: $($_.Exception.Message)" 'WARN' }
            }
        }
    }

    $swEntry = [System.Diagnostics.Stopwatch]::StartNew()
    if ($KnownOnFolder) {
        $onFolder = $true
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms 0 -Extra 'result=True skipped=known_on_folder'
    } else {
        $onFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        $swEntry.Stop()
        Write-LaunchPerfLog -Mark 'entry_on_folder' -Ms $swEntry.ElapsedMilliseconds -Extra "result=$onFolder"
    }

    $swAgent = [System.Diagnostics.Stopwatch]::StartNew()
    $agentHome = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }
    $swAgent.Stop()
    Write-LaunchPerfLog -Mark 'entry_agent_home' -Ms $swAgent.ElapsedMilliseconds -Extra "result=$agentHome"

    $swProfile = [System.Diagnostics.Stopwatch]::StartNew()
    # Always @()-wrap: one main process must not look like Count=$null (orphan false-positive).
    $hasProfileWindow = if ($EditorCmd -eq 'cursor') { @(Get-CursorMainProfileProcesses).Count -gt 0 } else { $false }
    $profileProcCount = if ($EditorCmd -eq 'cursor') { @(Get-CursorProfileProcesses).Count } else { 0 }
    $swProfile.Stop()
    Write-LaunchPerfLog -Mark 'entry_profile_counts' -Ms $swProfile.ElapsedMilliseconds -Extra "profile_main=$hasProfileWindow profile_all=$profileProcCount"

    # B11 settle: mainCount==0 && allCount>0 â†’ wait â‰¤3Ã—~400ms for sibling spinup, re-query.
    if ($EditorCmd -eq 'cursor' -and (-not $hasProfileWindow) -and ($profileProcCount -gt 0)) {
        for ($settle = 1; $settle -le 3; $settle++) {
            Start-Sleep -Milliseconds 400
            Clear-CursorProcessCache
            $hasProfileWindow = @(Get-CursorMainProfileProcesses).Count -gt 0
            $profileProcCount = @(Get-CursorProfileProcesses).Count
            Write-EditorLaunchLog ("LAUNCH_SETTLE attempt={0} profile_main={1} profile_all={2}" -f $settle, $hasProfileWindow, $profileProcCount) 'INFO'
            if ($hasProfileWindow -or ($profileProcCount -eq 0)) { break }
        }
    }

    # NEVER soft-stop ClaudeServerCursorProfile for auth. main=1 was a false signal when
    # many windows share one profile (profile_count=24 but only one "main" detected) and
    # wiped every remote window. Auth keys merge in-place into state.vscdb; no kill needed.
    if ($AuthRelaunch -and $EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        $mainCount = @(Get-CursorMainProfileProcesses).Count
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=auth_relaunch_never_kill profile_count={0} main={1}" -f $profileProcCount, $mainCount) 'INFO'
    }

    Write-EditorLaunchLog (
        "LAUNCH_BEGIN: exe=$cli editor=$EditorCmd alias=$Alias path=$RemotePath uri=$uri " +
        "on_folder=$onFolder agent_home=$agentHome profile_main=$hasProfileWindow profile_all=$profileProcCount " +
        "elevated=$(Test-IsElevatedShell) known_on_folder=$KnownOnFolder auth_relaunch=$AuthRelaunch"
    ) 'INFO'
    Write-EditorLaunchLog (
        "LAUNCH_PROBE profile_all=$profileProcCount profile_main=$hasProfileWindow agent_home=$agentHome on_folder=$onFolder"
    ) 'INFO'

    # $onFolder is now a project-scoped title/URI/cmd check (it no longer globally short-circuits on a
    # standalone "Cursor Agents" window), so it is authoritative on its own: if THIS project's window is
    # open, skip relaunch even when an unrelated agents window is also present. Gating on -not $agentHome
    # here made connect relaunch a project that was already open whenever a Cursor Agents window existed.
    if ($onFolder) {
        Write-EditorLaunchLog (
            "EDITOR_DECISION: skip_launch reason=already_on_folder on_folder=$onFolder agent_home=$agentHome " +
            "profile_main=$hasProfileWindow profile_all=$profileProcCount"
        ) 'INFO'
        Write-EditorLaunchLog 'LAUNCH_SKIP: already on correct folder - keeping Cursor open' 'INFO'
        $script:LaunchPerfSw.Stop()
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=skip'
        return $true
    }

    if ($script:VerboseLaunch) {
        Write-EditorLaunchVerboseState -Label 'BEGIN' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
    }

    # Parallel Connect cold-start race: serialize profile launch; re-query after wait.
    # Holder releases right after Start-Process — peer often still sees profile_all=0 for
    # several seconds. Old settle required profile_all>0 first, so it skipped and dual
    # cold_start without --new-window still happened (fleet W1+W2 same-ms shape).
    $launchGate = $null
    $gateWaited = $false
    if ($EditorCmd -eq 'cursor') {
        $launchGate = Enter-CursorProfileLaunchGate
        # Contended = waited OR timeout/fail (never dual reuse-window cold after peer pressure).
        $gateWaited = [bool]$launchGate.Contended -or ([int]$launchGate.WaitedMs -gt 0)
        Clear-CursorProcessCache
        $hasProfileWindow = @(Get-CursorMainProfileProcesses).Count -gt 0
        $profileProcCount = @(Get-CursorProfileProcesses).Count
        if ($gateWaited -and (-not $hasProfileWindow)) {
            # Always poll after a wait — even while profile_all is still 0 (peer cold boot).
            for ($settle = 1; $settle -le 12; $settle++) {
                Start-Sleep -Milliseconds 400
                Clear-CursorProcessCache
                $hasProfileWindow = @(Get-CursorMainProfileProcesses).Count -gt 0
                $profileProcCount = @(Get-CursorProfileProcesses).Count
                Write-EditorLaunchLog ("LAUNCH_GATE_SETTLE attempt={0} profile_main={1} profile_all={2} waited_ms={3}" -f $settle, $hasProfileWindow, $profileProcCount, $launchGate.WaitedMs) 'INFO'
                if ($hasProfileWindow) { break }
            }
        }
        $agentHome = Test-RemoteEditorInAgentHome -RemotePath $RemotePath
    }

    try {
    $plan = Get-CursorLaunchWindowPlan -AgentHome $agentHome -HasProfileWindow $hasProfileWindow -ProfileProcCount $profileProcCount
    $orphanHelpers = $plan.OrphanHelpers
    $useNewWindow = $plan.UseNewWindow
    $planReason = $plan.Reason
    # Still helpers-only after settle -> reap server-profile tree -> cold start (UseNewWindow=false).
    # NEVER reap after a gate wait: helpers may be the peer's mid cold-boot (gate releases at
    # Start-Process). Killing that tree races the holder and drops their window.
    if ($EditorCmd -eq 'cursor' -and $orphanHelpers) {
        if ($gateWaited) {
            Write-EditorLaunchLog ("LAUNCH_REAP_SKIP: orphan_helpers after gate wait - peer may be mid cold boot profile_all={0}" -f $profileProcCount) 'INFO'
            $orphanHelpers = $false
            $useNewWindow = $true
            $planReason = 'launch_gate_peer'
        } else {
            Write-EditorLaunchLog ("LAUNCH_REAP: orphan_helpers_reaped profile_all={0} - Stop-CursorServerProfileTree then cold" -f $profileProcCount) 'WARN'
            try { Stop-CursorServerProfileTree } catch {
                Write-EditorLaunchLog ("LAUNCH_REAP_FAIL: {0}" -f $_.Exception.Message) 'WARN'
            }
            Start-Sleep -Milliseconds 400
            Clear-CursorProcessCache
            $hasProfileWindow = $false
            $profileProcCount = 0
            $orphanHelpers = $false
            $useNewWindow = $false
            $planReason = 'orphan_helpers_reaped'
        }
    }
    # Belt: waited/contended on peer gate but still look cold — never dual reuse-window on shared profile.
    if ($EditorCmd -eq 'cursor' -and $gateWaited -and (-not $useNewWindow) -and ($planReason -eq 'cold_start' -or $planReason -eq 'orphan_helpers_reaped')) {
        $useNewWindow = $true
        $planReason = 'launch_gate_peer'
        Write-EditorLaunchLog ("LAUNCH_GATE_PEER: force use_new_window=1 after wait waited_ms={0} profile_all={1}" -f $launchGate.WaitedMs, $profileProcCount) 'INFO'
    }
    Write-EditorLaunchLog "LAUNCH_PLAN: use_new_window=$useNewWindow reason=$planReason profile_all=$profileProcCount" 'INFO'

    if ($EditorCmd -eq 'code') {
        $swInit = [System.Diagnostics.Stopwatch]::StartNew()
        Initialize-CodeServerProfile
        $swInit.Stop()
        Write-LaunchPerfLog -Mark 'launch_init_profile' -Ms $swInit.ElapsedMilliseconds
    }

    # Never force-kill the ClaudeServerCursorProfile tree before launch when a real
    # main/agent-home window is open. Helpers-only was already reaped above (orphan_helpers_reaped).
    # Prefer --new-window (via $useNewWindow = AgentHome -or HasProfileWindow) and keep other projects open.
    if ($EditorCmd -eq 'cursor' -and ($agentHome -or $useNewWindow) -and ($profileProcCount -gt 0)) {
        Write-EditorLaunchLog ("LAUNCH_KILL_SKIP: reason=preserve_open_windows profile_count={0} agent_home={1} use_new_window={2}" -f $profileProcCount, $agentHome, $useNewWindow) 'INFO'
        Write-LaunchPerfLog -Mark 'launch_kill_profile' -Ms 0 -Extra 'skipped=preserve_open_windows'
    }

    $swPlan = [System.Diagnostics.Stopwatch]::StartNew()
    # Warm = profile already has activity (windows or helpers). Prefer --remote (+ remote-classic
    # fallback); never barrage with folder-uri retries that interrupt the in-flight handoff.
    $warmHandoff = ($useNewWindow -and $profileProcCount -gt 0)
    $strategies = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$useNewWindow -WarmHandoff:$warmHandoff)
    $swPlan.Stop()
    Write-LaunchPerfLog -Mark 'launch_strategies_plan' -Ms $swPlan.ElapsedMilliseconds -Extra "count=$($strategies.Count) warm=$warmHandoff"
    Write-EditorLaunchLog "LAUNCH_STRATEGIES: count=$($strategies.Count) warm=$warmHandoff names=$($strategies.Name -join ',')" 'INFO'

    $attempt = 0
    $anyStarted = $false
    $script:LastLaunchAttempts = @()
    $script:LaunchSawOnFolderTick = $false
    $script:LaunchGraceRelaunchDone = $false
    # Baseline profile PIDs before any strategy starts - used to reap losing-strategy orphans
    # without touching windows that were already open (shared ClaudeServerCursorProfile).
    $baselineProfilePids = @()
    if ($EditorCmd -eq 'cursor') {
        try {
            $baselineProfilePids = @((Get-CursorProfileProcesses) | ForEach-Object { [int]$_.ProcessId } | Where-Object { $_ -gt 0 })
        } catch { $baselineProfilePids = @() }
    }
    $failedAttemptPids = @()
    # Warm + promising: skip remote-classic (IPC interrupt) and go to extended grace.
    $script:LaunchSkipWarmClassic = $false
    foreach ($strategy in $strategies) {
        if ($script:LaunchSkipWarmClassic -and $strategy.Name -eq 'remote-classic') {
            Write-EditorLaunchLog 'LAUNCH_SKIP: strategy=remote-classic reason=promising_handoff_in_flight' 'INFO'
            continue
        }
        $attempt++
        if ($attempt -gt 1 -and $EditorCmd -eq 'cursor') {
            # Do not wipe the profile tree on strategy retry -- other open projects must stay alive.
            # Losing-attempt orphan PIDs are reaped only after a confirmed on_folder winner.
            Write-EditorLaunchLog "LAUNCH_RETRY_NO_KILL: strategy=$($strategy.Name) preserving profile windows" 'DEBUG'
        }

        if ($script:VerboseLaunch) {
            Write-EditorLaunchSnapshot -Label "PRE_ATTEMPT_${attempt}_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }

        Write-EditorLaunchLog "LAUNCH_ATTEMPT: n=$attempt strategy=$($strategy.Name) args=$(Format-ProcessArgumentString -ArgumentList $strategy.Args)" 'INFO'

        # Bug 2 secondary signal: window-count-before-vs-after-this-attempt, captured fresh per
        # attempt (not once for the whole launch) so a later strategy's baseline isn't stale from
        # an earlier attempt's own window changes. Cursor's single-instance IPC handoff means a
        # repeat --folder-uri/--remote request against an ALREADY-RUNNING shared-profile process
        # hands the new window to that SAME pid via an in-process IPC channel - that pid's
        # Win32_Process.CommandLine is fixed at original process-creation time and never reflects
        # the newly-requested folder (see research note below Launch-RemoteEditor), so
        # CommandLine-based detection is permanently blind to this case. Title-based detection
        # (Test-RemoteEditorOnCorrectFolder, now fixed for the site-tag bug above) covers the
        # common case, but a real Win32 top-level-window-COUNT delta on the known main profile
        # pid(s) - present before this attempt started, re-checked every poll tick - is a second,
        # title-agnostic corroborating signal that a new window genuinely materialized for THIS
        # request, not just whatever text happens to be in a window's title at the instant we
        # look. Scoped to the handoff scenario only ($useNewWindow -and $profileProcCount -gt 0)
        # so cold-start launches (own fresh process, title/URI detection already reliable) are
        # unaffected. Window-count is PROMISING only - it must NOT return Launch success alone
        # (Confirm requires on_folder; P0.4 false "elevated launch failed").
        $preAttemptWindowCounts = @{}
        if ($EditorCmd -eq 'cursor') {
            foreach ($p in @(Get-CursorMainProfileProcesses)) {
                $preAttemptWindowCounts[$p.ProcessId] = @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId).Count
            }
        }

        $swStart = [System.Diagnostics.Stopwatch]::StartNew()
        if (-not (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strategy.Args)) {
            Write-EditorLaunchLog "LAUNCH_FAIL_START: strategy=$($strategy.Name) Start-ProcessAsInteractiveUser returned false" 'ERROR'
            continue
        }
        $swStart.Stop()
        Write-LaunchPerfLog -Mark 'start_process' -Ms $swStart.ElapsedMilliseconds -Extra "strategy=$($strategy.Name)"
        $anyStarted = $true
        # Release gate as soon as a process is spawned so a peer Connect can re-query and
        # take profile_open/--new-window instead of blocking through on_folder poll.
        if ($launchGate) {
            Exit-CursorProfileLaunchGate -Gate $launchGate
            $launchGate = $null
        }

        # Track PIDs this attempt introduced (for orphan reap after a later winner).
        $thisAttemptPids = @()
        if ($EditorCmd -eq 'cursor') {
            if ($script:LastEditorStartPid -gt 0) { $thisAttemptPids += [int]$script:LastEditorStartPid }
            try {
                Clear-CursorProcessCache
                $nowPids = @((Get-CursorProfileProcesses -ForceRefresh) | ForEach-Object { [int]$_.ProcessId } | Where-Object { $_ -gt 0 })
                foreach ($np in $nowPids) {
                    if ($baselineProfilePids -contains $np) { continue }
                    if ($failedAttemptPids -contains $np) { continue }
                    if ($thisAttemptPids -contains $np) { continue }
                    $thisAttemptPids += $np
                }
            } catch {}
        }

        $afterFolder = $false
        $afterAgent = $true
        $windowCountIncreased = $false
        # Poll every 250ms instead of sleeping a full 1s between checks - a ready window is
        # typically detected within one tick of becoming ready instead of up to ~900ms late.
        $pollMs = 250
        # Warm attempt 1: wall-clock 25s (tick count alone inflated to ~76s under ×6 CIM load —
        # Precise 20260804.16 W6 Opening Cursor=94268ms). Warm retries short.
        # Cold attempt 1: 48 ticks (12s). Cold retries keep 12 ticks.
        $pollMaxTicks =
            if ($attempt -gt 1 -and $useNewWindow -and $profileProcCount -gt 0) { 6 }
            elseif ($attempt -eq 1 -and $useNewWindow -and $profileProcCount -gt 0) { 100 }
            elseif ($attempt -eq 1) { 48 }
            else { 12 }
        $warmWallMs = if ($attempt -eq 1 -and $useNewWindow -and $profileProcCount -gt 0) { 25000 } else { 0 }
        $swPoll = [System.Diagnostics.Stopwatch]::StartNew()
        $promisingStreak = 0
        $onFolderStreak = 0
        $exitForPromisingGrace = $false
        for ($pollTick = 1; $pollTick -le $pollMaxTicks; $pollTick++) {
            if ($warmWallMs -gt 0 -and $swPoll.ElapsedMilliseconds -ge $warmWallMs) {
                Write-EditorLaunchLog ("LAUNCH_POLL_WALL: strategy={0} wall_ms={1} cap={2} - stop tick poll" -f $strategy.Name, $swPoll.ElapsedMilliseconds, $warmWallMs) 'INFO'
                break
            }
            Start-Sleep -Milliseconds $pollMs
            # Throttle full CIM refresh under fleet load (promising path).
            if (($pollTick % 2) -eq 1 -or $promisingStreak -lt 2) { Clear-CursorProcessCache }
            $afterFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
            $afterAgent = if ($EditorCmd -eq 'cursor') { Test-RemoteEditorInAgentHome -RemotePath $RemotePath } else { $false }

            # Promising secondary signal only (see comment above). Never return true on this alone.
            $windowCountIncreased = $false
            if ($EditorCmd -eq 'cursor' -and $useNewWindow -and $profileProcCount -gt 0) {
                foreach ($p in @(Get-CursorMainProfileProcesses)) {
                    $curWinCount = @(Get-ProcessTopLevelWindows -ProcessId $p.ProcessId).Count
                    $baseWinCount = 0
                    if ($preAttemptWindowCounts.ContainsKey($p.ProcessId)) { $baseWinCount = $preAttemptWindowCounts[$p.ProcessId] }
                    if ($curWinCount -gt $baseWinCount) { $windowCountIncreased = $true; break }
                }
            }
            $elapsedMs = [int]$swPoll.ElapsedMilliseconds
            Write-EditorLaunchLog (
                "LAUNCH_POLL: strategy=$($strategy.Name) elapsed=${elapsedMs}ms on_folder=$afterFolder agent_home=$afterAgent window_count_increased=$windowCountIncreased"
            ) 'DEBUG'
            Write-LaunchPerfLog -Mark "poll_${elapsedMs}ms" -Ms $elapsedMs -Extra "on_folder=$afterFolder strategy=$($strategy.Name)"

            # Unified success bar with Confirm-RemoteEditorLaunchVisible: on_folder ONLY.
            # window_count_increased is promising (keep polling) but must not return true -
            # that disagreement produced false StepFail "elevated launch failed" (P0.4).
            # Require 2 consecutive on_folder ticks under warm ×6 (single-tick flicker on dakhl).
            if ($afterFolder) {
                $onFolderStreak++
                $script:LaunchSawOnFolderTick = $true
            } else {
                $onFolderStreak = 0
            }
            $needStable = if ($useNewWindow -and $profileProcCount -gt 0) { 2 } else { 1 }
            if ($afterFolder -and $onFolderStreak -ge $needStable) {
                Write-EditorLaunchLog "LAUNCH_OK: strategy=$($strategy.Name) attempt=$attempt reason=on_folder agent_home=$afterAgent streak=$onFolderStreak" 'INFO'
                $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent:wincount=$windowCountIncreased"
                if ($EditorCmd -eq 'cursor' -and $failedAttemptPids.Count -gt 0) {
                    $keepPids = @($baselineProfilePids + $thisAttemptPids)
                    try {
                        $keepPids += @((Get-CursorMainProfileProcesses) | ForEach-Object { [int]$_.ProcessId })
                    } catch {}
                    [void](Stop-EditorLaunchAttemptOrphans -KeepPids $keepPids -CandidatePids $failedAttemptPids)
                }
                $script:LaunchPerfSw.Stop()
                Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra "path=ok strategy=$($strategy.Name)"
                return $true
            }
            if ($windowCountIncreased -and -not $afterAgent) {
                $promisingStreak++
                Write-EditorLaunchLog (
                    "LAUNCH_PROMISING: strategy=$($strategy.Name) reason=window_count_increased_no_title_match streak=$promisingStreak - waiting for on_folder"
                ) 'DEBUG'
                # Sustained promising under ×6: skip remote-classic only if we already saw on_folder
                # at least once (flicker). Early grace without any on_folder → started_but_no_process
                # after 45s (Precise×6 20260804.32 R2 deploy).
                if ($promisingStreak -ge 6 -and $useNewWindow -and $profileProcCount -gt 0 -and $elapsedMs -ge 8000 -and $script:LaunchSawOnFolderTick) {
                    Write-EditorLaunchLog ("LAUNCH_PROMISING_EARLY_GRACE: strategy={0} wall_ms={1} saw_on_folder=1" -f $strategy.Name, $elapsedMs) 'INFO'
                    $script:LaunchSkipWarmClassic = $true
                    $exitForPromisingGrace = $true
                    break
                }
            } else {
                $promisingStreak = 0
            }

            if ($script:VerboseLaunch -and $pollTick -eq $pollMaxTicks) {
                Write-EditorLaunchVerboseState -Label "POLL_${elapsedMs}ms_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
            }
        }

        Write-EditorLaunchLog (
            "LAUNCH_ATTEMPT_RESULT: n=$attempt strategy=$($strategy.Name) on_folder=$afterFolder agent_home=$afterAgent " +
            "window_count_increased=$windowCountIncreased $(Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
        ) 'INFO'
        $script:LastLaunchAttempts += "${attempt}:$($strategy.Name):folder=$afterFolder:agent=$afterAgent:wincount=$windowCountIncreased"
        if ($thisAttemptPids.Count -gt 0) {
            $failedAttemptPids = @($failedAttemptPids + $thisAttemptPids | Select-Object -Unique)
        }
        if ($script:VerboseLaunch) {
            Write-EditorLaunchVerboseState -Label "RESULT_$($strategy.Name)" -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot
        }

        if ($exitForPromisingGrace) {
            # Do not WARN LAUNCH_RETRY — handoff in flight; grace is the next step.
            break
        }
        # Cascade to next strategy is expected under warm ×6 — INFO; final LAUNCH_WARN stays WARN.
        Write-EditorLaunchLog "LAUNCH_RETRY: strategy=$($strategy.Name) did not reach target folder - next strategy" 'INFO'
    }

    # Warm grace: the --remote IPC handoff may still be settling (same-window title update).
    # Extended when promising early-exit (×6 title settle can take 30–60s wall).
    if ($anyStarted -and $warmHandoff) {
        # Default warm grace 30s (was 10s) — last Parallel slot under ×6 often needs it.
        # Promising early-exit keeps 45s.
        $graceTicks = if ($script:LaunchSkipWarmClassic) { 240 } else { 160 }
        Write-EditorLaunchLog ("LAUNCH_GRACE: warm handoff - waiting up to {0}s more for on_folder" -f ([int]($graceTicks * 0.25))) 'INFO'
        $graceOnFolderStreak = 0
        for ($g = 1; $g -le $graceTicks; $g++) {
            Start-Sleep -Milliseconds 250
            Clear-CursorProcessCache
            # Mid-grace: profile tree vanished under ×6 sibling pressure — one cold relaunch.
            if ($EditorCmd -eq 'cursor' -and ((@(Get-CursorMainProfileProcesses).Count) -eq 0) -and -not $script:LaunchGraceRelaunchDone) {
                $script:LaunchGraceRelaunchDone = $true
                Write-EditorLaunchLog 'LAUNCH_GRACE_RELAUNCH: profile_empty mid-grace - cold remote once' 'INFO'
                try {
                    $reArgs = $null
                    foreach ($st in @($strategies)) {
                        if ($st.Name -eq 'remote') { $reArgs = $st.Args; break }
                    }
                    if ($reArgs) {
                        [void](Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $reArgs)
                    }
                } catch {
                    Write-EditorLaunchLog ("LAUNCH_GRACE_RELAUNCH_FAIL: {0}" -f $_.Exception.Message) 'INFO'
                }
                continue
            }
            if (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) {
                $graceOnFolderStreak++
            } else {
                $graceOnFolderStreak = 0
            }
            if ($graceOnFolderStreak -ge 2) {
                Write-EditorLaunchLog ("LAUNCH_OK: strategy=grace attempt=post reason=on_folder elapsed={0}ms streak=2" -f ($g * 250)) 'INFO'
                $script:LastLaunchAttempts += "grace:on_folder"
                if ($EditorCmd -eq 'cursor' -and $failedAttemptPids.Count -gt 0) {
                    $keepPids = @($baselineProfilePids)
                    try {
                        $keepPids += @((Get-CursorMainProfileProcesses) | ForEach-Object { [int]$_.ProcessId })
                    } catch {}
                    [void](Stop-EditorLaunchAttemptOrphans -KeepPids $keepPids -CandidatePids $failedAttemptPids)
                }
                $script:LaunchPerfSw.Stop()
                Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=ok strategy=grace'
                return $true
            }
        }
    }

    Write-EditorLaunchVerboseState -Label 'EXHAUSTED' -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -IncludeSnapshot -ForceLog
    $script:LaunchPerfSw.Stop()
    if (-not $anyStarted) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: all strategies failed to start process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail'
        return $false
    }

    Clear-CursorProcessCache
    $profileProcs = @(Get-EditorProfileProcessesForLaunch -EditorCmd $EditorCmd -ForceRefresh)
    if ($profileProcs.Count -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_process'
        return $false
    }

    $mainCount = if ($EditorCmd -eq 'cursor') {
        @(Get-CursorMainProfileProcesses).Count
    } else {
        @($profileProcs | Where-Object { $_.CommandLine -and ($_.CommandLine -notmatch '--type=') }).Count
    }
    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath

    Write-EditorLaunchLog 'LAUNCH_WARN: process started but folder workspace not detected - press O to retry' 'WARN'
    if ($mainCount -eq 0) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_no_process main_count=0' 'ERROR'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_no_main'
        return $false
    }
    if (-not $windowOpen) {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_wrong_or_no_folder_window' 'ERROR'
    } else {
        Write-EditorLaunchLog 'LAUNCH_FAIL: started_but_not_on_folder' 'ERROR'
    }

    # H2/H3 CONFIRMED (debug session c46ba1, live repro 2026-07-24): when another project's
    # window is already open on this shared profile, Cursor's --new-window IPC handoff to the
    # existing instance never produces a detectable second window (CommandLine-based on_folder
    # check keeps inspecting the SAME pre-existing pid, whose original CommandLine points at the
    # OTHER project and never changes) - all 4 strategies exhaust their poll budget (~56s) and
    # this recovery block used to Stop-CursorServerProfileTree, force-closing that OTHER
    # project's fully-working window (main + gpu/utility/renderer helpers) just to cold-launch
    # this one. Must mirror the same preserve_open_windows guard used before the attempts
    # (LAUNCH_KILL_SKIP above) - never destroy someone else's open Cursor session as a "recovery".
    #
    # Bug 8 fix: deliberately narrower than the earlier LAUNCH_KILL_SKIP guard at ~line 2070
    # (which uses the broader $useNewWindow). $useNewWindow is unconditionally true whenever
    # $profileProcCount -gt 0 - either directly via $hasProfileWindow, OR via $orphanHelpers
    # (Get-CursorLaunchWindowPlan) when $hasProfileWindow is FALSE but stale/invisible helper
    # processes exist. Reusing $useNewWindow here made $preservedOpenWindows always mirror the
    # very next `if`'s own "$profileProcCount -gt 0" guard, so LAUNCH_RECOVERY_SKIP fired every
    # time and the soft_stop_profile/cold_launch recovery block below was provably unreachable
    # (proven by test-launch-recovery-reachable-live.ps1 across all 12 (agentHome,
    # hasProfileWindow, profileProcCount) combinations). What this guard is ACTUALLY meant to
    # protect is a real, visible open window (or agent-home) - not the mere existence of orphan
    # helper processes with no window at all.
    #
    # Bug 14 fix (2026-07-24, live repro): $hasProfileWindow is captured ONCE at function ENTRY
    # (~line 2048), before this call's own up-to-4 launch attempts and up to ~40s of retries even
    # begin. By the time this post-exhaustion decision runs, it can be stale by tens of seconds -
    # confirmed live: a genuinely open, unrelated project's window (real main pid, alive the whole
    # time) was NOT protected because entry-time $hasProfileWindow no longer reflected current
    # reality, so Stop-CursorServerProfileTree killed that real window's whole process tree just to
    # cold-launch this one. $mainCount (line 2254) is a FRESH re-query of the exact same signal,
    # taken moments before this exact decision - use that instead of the stale entry-time value.
    # Do NOT swap this back to $useNewWindow (re-collapses the Bug 8 guard) or to $hasProfileWindow
    # (re-introduces Bug 14's stale-read window-kill).
    $preservedOpenWindows = ($EditorCmd -eq 'cursor' -and ($agentHome -or ($mainCount -gt 0)) -and ($profileProcCount -gt 0))
    if ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0 -and $preservedOpenWindows) {
        Write-EditorLaunchLog ("LAUNCH_RECOVERY_SKIP: reason=preserve_open_windows profile_count={0} - not killing other open project windows; press O to retry" -f $profileProcCount) 'WARN'
        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_preserved_open_windows'
        return $false
    }
    if ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0) {
        Write-EditorLaunchLog ("LAUNCH_RECOVERY: soft_stop_profile then cold_launch path={0}" -f $RemotePath) 'WARN'
        try { Stop-CursorServerProfileTree } catch {
            Write-EditorLaunchLog ("LAUNCH_RECOVERY_KILL_FAIL: {0}" -f $_.Exception.Message) 'WARN'
        }
        Start-Sleep -Milliseconds 400
        Clear-CursorProcessCache
        $cold = @(Get-RemoteEditorLaunchStrategies -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath -Uri $uri -NewWindow:$false)
        if ($cold.Count -gt 0) {
            $strat = $cold[0]
            Write-EditorLaunchLog ("LAUNCH_RECOVERY_ATTEMPT: strategy={0}" -f $strat.Name) 'INFO'
            if (Start-ProcessAsInteractiveUser -FilePath $cli -ArgumentList $strat.Args) {
                # A cold Cursor.exe start after soft_stop_profile has to spin up its whole
                # process tree (crashpad, gpu, utility, renderer) from disk with no warm
                # profile process to reuse - on a loaded machine (many unrelated Cursor.exe
                # processes competing for CPU/IO) this routinely takes well over the old
                # 10s budget (20*500ms). Give it a much more realistic ceiling (45s) so a
                # launch that is genuinely succeeding isn't reported as failed while the
                # window is still on its way up (confirmed live: window appeared correctly
                # ~30-60s after this loop used to give up).
                for ($tick = 1; $tick -le 90; $tick++) {
                    Start-Sleep -Milliseconds 500
                    Clear-CursorProcessCache
                    if ((Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath) -and
                        -not (Test-RemoteEditorInAgentHome -RemotePath $RemotePath)) {
                        Write-EditorLaunchLog ("LAUNCH_OK: recovery_cold_start elapsed_ms={0}" -f ($tick * 500)) 'INFO'
                        Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=ok_recovery'
                        return $true
                    }
                }
            }
        }
        Write-EditorLaunchLog 'LAUNCH_RECOVERY_FAIL: cold_start_did_not_reach_folder' 'ERROR'
    }

    Write-LaunchPerfLog -Mark 'launch_total' -Ms $script:LaunchPerfSw.ElapsedMilliseconds -Extra 'path=fail_not_on_folder'
    return $false
    } finally {
        if ($launchGate) {
            Exit-CursorProfileLaunchGate -Gate $launchGate
            $launchGate = $null
        }
    }
}

