from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1')
t = p.read_text(encoding='utf-8')
old = '''    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
    $remote = "echo $b64 | base64 -d | bash"
    # Record before the call so nested/re-entrant startup paths cannot duplicate the same push.
    $script:LastPushConfKey = $dedupeKey
    $script:LastPushConfAt = Get-Date
    $pushOut = @(SshX $remote 2>$null)
    $pushExit = $global:LASTEXITCODE
    $pushLine = (($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1) -replace '\\s+', ' ').Trim()
    if (-not $pushLine) { $pushLine = '(no result line)' }
    if ($pushExit -ne 0) {
        Write-GitModeLog "PUSH_CONF fail exit=$pushExit out=$pushLine" 'ERROR'
    } else {
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
}'''
new = '''    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
    $remote = "echo $b64 | base64 -d | bash"
    $pushOut = @(SshX $remote 2>$null)
    $pushExit = $global:LASTEXITCODE
    $pushLine = (($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1) -replace '\\s+', ' ').Trim()
    if (-not $pushLine) { $pushLine = '(no result line)' }
    if ($pushExit -ne 0) {
        # Do not record dedupe on failure — allow immediate retry of the same prefer/clear key.
        Write-GitModeLog "PUSH_CONF fail exit=$pushExit out=$pushLine" 'ERROR'
    } else {
        $script:LastPushConfKey = $dedupeKey
        $script:LastPushConfAt = Get-Date
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
}'''
# file may use actual whitespace not escaped
old = old.replace('\\\\s+', '\\s+')
new = new.replace('\\\\s+', '\\s+')
if old not in t:
    # try reading exact snippet
    idx = t.find('$remote = "echo $b64 | base64 -d | bash"')
    print('IDX', idx)
    print(repr(t[idx:idx+700]))
    raise SystemExit('block not found')
t = t.replace(old, new, 1)
# also promote skip_duplicate to INFO
t2 = t.replace(
    'Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" \'DEBUG\'',
    'Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" \'INFO\'',
    1,
)
if t2 == t:
    print('WARN skip_duplicate level not changed')
else:
    t = t2
    print('promoted skip_duplicate to INFO')
p.write_text(t, encoding='utf-8', newline='\n')
print('OK dedupe-on-success-only')
