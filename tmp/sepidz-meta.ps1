$p = "D:/Smart/Claude-Code-Server/publish/sepidz-deploy.local.ps1"
$t = Get-Content -LiteralPath $p -Raw
function Grab([string]$name) {
  $pat1 = '(?m)^\s*\$' + [regex]::Escape($name) + "\s*=\s*'([^']*)'"
  $m = [regex]::Match($t, $pat1)
  if ($m.Success) { return $m.Groups[1].Value }
  $pat2 = '(?m)^\s*\$' + [regex]::Escape($name) + '\s*=\s*"([^"]*)"'
  $m = [regex]::Match($t, $pat2)
  if ($m.Success) { return $m.Groups[1].Value }
  return ""
}
$user = Grab "SepidzSshUser"; if (-not $user) { $user = "sepidz" }
$host_ = Grab "SepidzServerIp"; if (-not $host_) { $host_ = "192.168.250.70" }
$pw = Grab "SepidzSudoPassword"
Write-Output ("user=" + $user)
Write-Output ("host=" + $host_)
Write-Output ("hasPassword=" + (-not [string]::IsNullOrWhiteSpace($pw)))
Write-Output ("pwLen=" + $pw.Length)
