$ErrorActionPreference = 'Continue'
$files = @(
  'scripts/client/users/designer/connect.ps1',
  'scripts/client/windows/connect-design.ps1',
  'scripts/client/connect-ui.ps1',
  'scripts/client/windows/connect.ps1'
)
$fail = 0
foreach ($f in $files) {
  $tokens = $null; $errors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors)
  if ($errors -and $errors.Count -gt 0) {
    Write-Host "PARSE_FAIL $f"
    $errors | ForEach-Object { Write-Host ("  L{0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
    $fail++
  } else { Write-Host "PARSE_OK $f" }
}
$hits = 0
function Hit([string]$name, [bool]$bad) {
  if ($bad) { Write-Host "HIT $name"; $script:hits++ } else { Write-Host "OK  $name" }
}
$d = Get-Content 'scripts/client/users/designer/connect.ps1' -Raw
$cd = Get-Content 'scripts/client/windows/connect-design.ps1' -Raw
$ui = Get-Content 'scripts/client/connect-ui.ps1' -Raw
# Default seed before wait: action = 'q' on its own line near FlushKeys/KeyAvailable setup
Hit 'designer-seed-action-q' ([regex]::IsMatch($d, "(?m)^\s*\$action = 'q'\s*$"))
Hit 'design-seed-action-q' ([regex]::IsMatch($cd, "(?m)^\s*\$action = 'q'\s*$"))
Hit 'designer-ActiveMount-empty' ($d -match "ActiveMount ''")
Hit 'designer-missing-Clear' ($d -notmatch 'ClearActiveMount')
Hit 'designer-missing-useVk' ($d -notmatch '\$useVk')
Hit 'designer-missing-mutex' ($d -notmatch 'Enter-ConnectSingleInstance')
Hit 'design-missing-useVk' ($cd -notmatch '\$useVk')
Hit 'design-missing-mutex' ($cd -notmatch 'Enter-ConnectSingleInstance')
Hit 'ui-missing-ConnectUiReady' ($ui -notmatch 'ConnectUiReady')
Hit 'ui-Wait-ungated-ReadHost' ($ui -notmatch 'if \(\$script:ConnectUiReady\)')
# ungated Key -eq Q without useVk nearby in same elseif (heuristic)
Hit 'design-ungated-or-Key-Q' ([regex]::IsMatch($cd, "(?s)KeyChar\.ToString\(\)\.ToLower\(\).*?-eq 'q'.*?-or.*?ConsoleKey\]::Q"))
Write-Host "hits=$hits parse_fail=$fail"
if ($fail -gt 0 -or $hits -gt 0) { exit 1 } else { Write-Host 'ALL_PASS'; exit 0 }
