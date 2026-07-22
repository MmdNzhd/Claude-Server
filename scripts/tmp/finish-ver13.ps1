Set-Location D:\Smart\Claude-Code-Server
$ver = '20260720.13'
$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Retry([string]$Path, [string]$Text) {
  for ($i=0; $i -lt 15; $i++) {
    try {
      [IO.File]::WriteAllText($Path, $Text, $utf8)
      return $true
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  return $false
}
if (-not (Write-Retry (Join-Path (Get-Location) 'scripts\client\windows\connect-version.txt') ($ver + "`n"))) { throw 'win ver locked' }
if (-not (Write-Retry (Join-Path (Get-Location) 'scripts\client\mac\connect-version.txt') ($ver + "`n"))) { Write-Host 'WARN mac ver locked' -ForegroundColor Yellow }

$winPath = Resolve-Path 'scripts/client/windows/connect.ps1'
$w = [IO.File]::ReadAllText($winPath)
$w2 = [regex]::Replace($w, "(?m)^\`$script:ConnectVersion = '20260720\.\d+'\s*$", "`$script:ConnectVersion = '$ver'")
if ($w2 -ne $w) { [IO.File]::WriteAllText($winPath, $w2, $utf8) }

$macPath = Resolve-Path 'scripts/client/mac/connect.sh'
$m = [IO.File]::ReadAllText($macPath)
$m2 = [regex]::Replace($m, "CONNECT_VERSION='20260720\.\d+'", "CONNECT_VERSION='$ver'")
if ($m2 -ne $m) { [IO.File]::WriteAllText($macPath, $m2, $utf8) }

Write-Host ("ver_file=" + (Get-Content scripts/client/windows/connect-version.txt -Raw).Trim())
Write-Host ("ps1=" + [regex]::Match([IO.File]::ReadAllText($winPath), "ConnectVersion = '[^']+'").Value)
Write-Host ("bat_has_start=" + ([IO.File]::ReadAllText((Resolve-Path 'scripts/client/windows/connect.bat')) -match 'start "" /D "%HERE%"'))
$tok=$null;$err=$null
$null=[Management.Automation.Language.Parser]::ParseFile($winPath,[ref]$tok,[ref]$err)
if ($err -and $err.Count) { throw ($err | Out-String) }
Write-Host 'PARSE_OK'
