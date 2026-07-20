$ErrorActionPreference='Continue'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')
Get-Command -Name 'Get-*Sepidz*','Get-*Smart*','Get-*Deploy*' -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host ("FUNC {0}" -f $_.Name)
}
# Show function bodies (names only of vars, redact values when printing results)
$funcs = @(
  'Get-SepidzServerTarget','Get-SepidzSudoPassword','Get-SepidzSshPassword',
  'Get-SmartServerTarget','Get-SmartSudoPassword','Get-DeployCredentials'
)
foreach ($f in $funcs) {
  $cmd = Get-Command $f -ErrorAction SilentlyContinue
  if (-not $cmd) { Write-Host "MISSING $f"; continue }
  Write-Host "==== $f ===="
  Write-Host ($cmd.ScriptBlock.ToString().Substring(0,[Math]::Min(800,$cmd.ScriptBlock.ToString().Length)))
}
# List vars defined by local file without printing secret values
$raw = Get-Content publish/sepidz-deploy.local.ps1 -Raw
[regex]::Matches($raw, '\$([A-Za-z_][A-Za-z0-9_]*)\s*=') | ForEach-Object { Write-Host ("VAR {0}" -f $_.Groups[1].Value) }
Write-Host ("HasSudo={0}" -f [bool](Get-SepidzSudoPassword))
if (Get-Command Get-SepidzSshPassword -EA SilentlyContinue) {
  Write-Host ("HasSshPw={0}" -f [bool](Get-SepidzSshPassword))
}
