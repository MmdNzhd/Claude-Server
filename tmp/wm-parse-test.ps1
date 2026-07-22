$ErrorActionPreference = 'Continue'
$wp = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260721.log.sync-offset'
Write-Output ("file=" + $wp)
Write-Output ("rawbytes=" + [BitConverter]::ToString([IO.File]::ReadAllBytes($wp)))
# Exact expression from connect-ui.ps1
$raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
Write-Output ("broken_expr_raw=[$raw]")
$n = 0
Write-Output ("broken_parse=" + [int]::TryParse($raw, [ref]$n) + " n=$n")
# Correct expression
$raw2 = ((Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue) + '').Trim()
$n2 = 0
Write-Output ("fixed_expr_raw=[$raw2] parse=" + [int]::TryParse($raw2, [ref]$n2) + " n=$n2")
# What does parser bind?
$cmd = { Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '' }
Write-Output ("ast=" + $cmd.Ast.Extent.Text)
# Simulate Write then Read immediately like reconcile
Set-Content -LiteralPath $wp -Value '999999' -Encoding ASCII -NoNewline -ErrorAction Stop
$raw3 = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
$n3=0; [void][int]::TryParse($raw3, [ref]$n3)
Write-Output ("after_write_999999 broken_read=$n3 file=$((Get-Content $wp -Raw))")
# restore
Set-Content -LiteralPath $wp -Value '524288' -Encoding ASCII -NoNewline
