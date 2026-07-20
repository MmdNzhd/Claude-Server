$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
$gs = [IO.File]::ReadAllText((Join-Path $root 'scripts/client/git-mode.sh'))
$gp = [IO.File]::ReadAllText((Join-Path $root 'scripts/client/git-mode.ps1'))
$cpBytes = [IO.File]::ReadAllBytes((Join-Path $root 'scripts/client/windows/connect.ps1'))
$cp = [Text.Encoding]::UTF8.GetString($cpBytes)

function Hit([string]$name, [bool]$ok) {
  if ($ok) { Write-Output ("PASS $name") } else { Write-Output ("FAIL $name"); $script:failed++ }
}

$script:failed = 0
Hit 'mac-seq-12-present' ($gs -match 'seq 1 12')
Hit 'mac-seq-4-absent' ($gs -notmatch 'seq 1 4')
Hit 'mac-recover' (($gs -match 'sshx "timeout 30 \$CM recover-one') -and ($gs -notmatch 'timeout 30 sshx "\$CM recover-one'))
Hit 'win-banner-budget' ($gp -match 'banner_miss_tcp_open_budget')
Hit 'win-action-reseed' ($gp -match 'action=reseed')
$curly = @([char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019)
$hasCurly = $false
foreach ($c in $curly) { if ($cp.IndexOf($c) -ge 0) { $hasCurly = $true; break } }
Hit 'connect-no-curly' (-not $hasCurly)

if ($script:failed -eq 0) { Write-Output 'P0_ALL_PASS'; exit 0 } else { Write-Output ("P0_FAILED=$script:failed"); exit 1 }
