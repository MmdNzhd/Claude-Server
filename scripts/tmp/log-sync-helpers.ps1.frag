function Get-ConnectLogSyncPendingPath {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath) { $LogPath = Get-ConnectLogDayPath }
    return ($LogPath + '.sync-pending')
}

function Clear-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (Test-Path -LiteralPath $pp) { Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Write-ConnectLogSyncPending {
    param(
        [int]$Offset,
        [int]$Take,
        [int64]$RemoteBefore,
        [string]$LogPath = $script:ConnectLogPath
    )
    try {
        $line = '{0}|{1}|{2}' -f $Offset, $Take, $RemoteBefore
        Set-Content -LiteralPath (Get-ConnectLogSyncPendingPath -LogPath $LogPath) -Value $line -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    } catch { }
}

function Read-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (-not (Test-Path -LiteralPath $pp)) { return $null }
        $raw = ((Get-Content -LiteralPath $pp -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($raw -notmatch '^(\d+)\|(\d+)\|(\d+)$') { return $null }
        return [PSCustomObject]@{
            Offset       = [int]$Matches[1]
            Take         = [int]$Matches[2]
            RemoteBefore = [int64]$Matches[3]
        }
    } catch { return $null }
}

function Get-ConnectRemoteLogByteSize {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [string[]]$SshOpts
    )
    # Lightweight remote size probe. -1 = probe failed (do not treat as reconcile success).
    $cmd = 'stat -c%s "$HOME/.claude/logs/connect-' + $Day + '.log" 2>/dev/null || echo 0'
    try {
        $argList = @()
        if ($SshOpts) { $argList += $SshOpts }
        $argList += @('-o', 'ConnectTimeout=6', $Target, $cmd)
        $raw = (& ssh @argList 2>$null | Out-String).Trim()
        $digits = ($raw -replace '[^0-9]', '')
        if (-not $digits) { return [int64](-1) }
        return [int64]$digits
    } catch {
        return [int64](-1)
    }
}

function Test-ConnectLogChunkAlreadyRemote {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [Parameter(Mandatory)][byte[]]$Chunk,
        [Parameter(Mandatory)][int]$Take,
        [string[]]$SshOpts
    )
    # Idempotency: if remote tail bytes match the chunk we are about to send, skip append.
    if ($Take -le 0 -or $Take -gt 524288) { return $false }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $localHash = ([BitConverter]::ToString($sha.ComputeHash($Chunk))).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
    } catch { return $false }
    $cmd = 'f="$HOME/.claude/logs/connect-' + $Day + '.log"; if [ ! -f "$f" ]; then echo none; exit 0; fi; sz=$(stat -c%s "$f" 2>/dev/null || echo 0); if [ "$sz" -lt ' + $Take + ' ]; then echo short; exit 0; fi; tail -c ' + $Take + ' "$f" | sha256sum | awk ''{print $1}'''
    try {
        $argList = @()
        if ($SshOpts) { $argList += $SshOpts }
        $argList += @('-o', 'ConnectTimeout=8', $Target, $cmd)
        $raw = ((& ssh @argList 2>$null) | Out-String).Trim().ToLowerInvariant()
        $remoteHash = ($raw -replace '[^0-9a-f]', '')
        if ($remoteHash.Length -ge 64) { $remoteHash = $remoteHash.Substring(0, 64) }
        return ($remoteHash -eq $localHash)
    } catch { return $false }
}

