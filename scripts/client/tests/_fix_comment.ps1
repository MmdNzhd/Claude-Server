$ErrorActionPreference = 'Stop'
$path = (Resolve-Path 'scripts\client\windows\connect.ps1').Path
$utf8 = New-Object System.Text.UTF8Encoding $false
$c = [IO.File]::ReadAllText($path, $utf8)
$old = '# Re-probe live mount before terminal RECOVERY_END (claimed MountOk can race SSHFS down).'
$new = '# Re-probe live mount before terminal recovery-end log (claimed MountOk can race SSHFS down).'
if (-not $c.Contains($old)) { throw 'comment not found' }
$c2 = $c.Replace($old, $new)
[IO.File]::WriteAllText($path + '.tmpfix', $c2, $utf8)
[IO.File]::Copy($path + '.tmpfix', $path, $true)
[IO.File]::Delete($path + '.tmpfix')
Write-Host 'FIXED_COMMENT'
& (Join-Path $PSScriptRoot 'test-mount-ok-reassert-before-recovery-end.ps1')
Write-Host ('EXIT=' + $LASTEXITCODE)
