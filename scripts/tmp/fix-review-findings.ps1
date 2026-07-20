$ErrorActionPreference = 'Stop'

# 1) Fix curly/smart quotes in connect.ps1 — find non-ASCII quote chars
$winPath = 'scripts/client/windows/connect.ps1'
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $winPath))
$text = [Text.Encoding]::UTF8.GetString($bytes)
$smart = @([char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019, [char]0x2014, [char]0x2026)
$found = @()
for ($i = 0; $i -lt $text.Length; $i++) {
    if ($smart -contains $text[$i]) {
        $start = [Math]::Max(0, $i - 40)
        $len = [Math]::Min(80, $text.Length - $start)
        $found += "pos=$i context=$($text.Substring($start,$len) -replace "`r|`n",' ')"
    }
}
Write-Host "SMART_QUOTE_HITS=$($found.Count)"
$found | Select-Object -First 20 | ForEach-Object { Write-Host $_ }

$fixed = $text.Replace([string][char]0x201C, '"').Replace([string][char]0x201D, '"').Replace([string][char]0x2018, "'").Replace([string][char]0x2019, "'")
# also common mojibake sequences from earlier logs
$fixed = $fixed -replace 'A<"���[^"]*"', '"'  # best-effort; may no-op
if ($fixed -ne $text) {
    [IO.File]::WriteAllText((Resolve-Path $winPath), $fixed)
    Write-Host 'OK rewrote connect.ps1 quotes'
} else {
    Write-Host 'NOTE no smart quotes replaced via char map — checking test pattern'
}

# Show what the curly-quote test looks for
$t = Get-Content 'scripts/client/tests/test-connect-pipeline.ps1' -Raw
if ($t -match 'curly quotes[\s\S]{0,400}') { Write-Host $Matches[0].Substring(0,[Math]::Min(400,$Matches[0].Length)) }

# 2) Fix Mac ensure_session_tunnel — read around line 1000
$sh = Get-Content 'scripts/client/git-mode.sh'
Write-Host '--- ensure_session_tunnel region ---'
for ($i = 980; $i -lt [Math]::Min(1050, $sh.Count); $i++) {
    '{0,5}|{1}' -f ($i+1), $sh[$i]
}
