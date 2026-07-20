$ErrorActionPreference = 'Stop'
# scripts/tmp -> repo root
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
Write-Host "cwd=$repoRoot"

function Repair-UnicodeFile([string]$Rel) {
    $full = Join-Path $repoRoot $Rel
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host "SKIP missing $Rel"
        return
    }
    $bytes = [IO.File]::ReadAllBytes($full)
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hadBom) {
        $bytes = $bytes[3..($bytes.Length-1)]
    }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $orig = $text
    $repl = @(
        @{ From = [char]0x201C; To = '"' },
        @{ From = [char]0x201D; To = '"' },
        @{ From = [char]0x2018; To = "'" },
        @{ From = [char]0x2019; To = "'" },
        @{ From = [char]0x2013; To = '-' },
        @{ From = [char]0x2014; To = '-' }
    )
    foreach ($r in $repl) {
        $text = $text.Replace([string]$r.From, [string]$r.To)
    }
    if ($text -ne $orig -or $hadBom) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($full, $text, $utf8NoBom)
        Write-Host ("FIXED {0} bom={1} textChanged={2}" -f $Rel, $hadBom, ($text -ne $orig))
    } else {
        Write-Host ("OK {0}" -f $Rel)
    }
}

$targets = @(
  'scripts\client\windows\connect.ps1',
  'scripts\client\connect-ui.ps1',
  'scripts\client\git-mode.ps1',
  'scripts\client\git-mode.sh',
  'scripts\client\cursor-auth-laptop.ps1',
  'scripts\client\windows\connect-update.ps1',
  'scripts\client\mac\connect.sh',
  'scripts\client\mac\connect-update.sh',
  'scripts\client\editor-launch.sh',
  'scripts\client\push-laptop-exec-now.ps1',
  'scripts\client\_deploy-sepidz-lex.ps1',
  'publish\deploy-client-bundles.ps1',
  'publish\Get-DeployCredentials.ps1',
  'publish\sepidz-deploy.local.ps1.example',
  'publish\smart-deploy.local.ps1.example'
)
foreach ($t in $targets) { Repair-UnicodeFile $t }

$path = Join-Path $repoRoot 'scripts\client\windows\connect.ps1'
$src = Get-Content $path -Raw
$ok = $src -notmatch '[\u201C\u201D\u2018\u2019]'
Write-Host ("ASSERT connect.ps1 no curly (default encoding): $ok")
if (-not $ok) {
    for ($i=0; $i -lt $src.Length; $i++) {
        $c = [int][char]$src[$i]
        if ($c -in 0x201C,0x201D,0x2018,0x2019) {
            $line = ($src.Substring(0,$i) -split "`n").Count
            Write-Host ("HIT U+{0:X4} at line {1} context=[{2}]" -f $c, $line, $src.Substring([Math]::Max(0,$i-20), [Math]::Min(40, $src.Length-[Math]::Max(0,$i-20))))
        }
    }
}

# Also assert connect-ui after fix
$ui = Get-Content (Join-Path $repoRoot 'scripts\client\connect-ui.ps1') -Raw
Write-Host ("ASSERT connect-ui.ps1 no curly (default): " + ($ui -notmatch '[\u201C\u201D\u2018\u2019]'))
Write-Host ("ASSERT connect-ui.ps1 no emdash utf8: " + (([IO.File]::ReadAllText((Join-Path $repoRoot 'scripts\client\connect-ui.ps1'), [Text.Encoding]::UTF8)) -notmatch '[\u2013\u2014]'))
