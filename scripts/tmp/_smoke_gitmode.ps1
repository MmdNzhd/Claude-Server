$ErrorActionPreference='Stop'
# Minimal stubs required by git-mode.ps1
function Write-ConnectLog { param($Message,$Level='INFO') }
function SshX { param([Parameter(ValueFromRemainingArguments=$true)]$Args) }
$Port = 21003
$script:ConnectLogPath = $null
. 'scripts\client\git-mode.ps1'
if(-not (Get-Command Get-TunnelBanner -EA SilentlyContinue)){ throw 'Get-TunnelBanner missing' }
if(-not (Get-Command Test-TunnelUp -EA SilentlyContinue)){ throw 'Test-TunnelUp missing' }
if(-not (Get-Command Sync-SessionTunnelProcess -EA SilentlyContinue)){ throw 'Sync missing' }
# Positive-cache only: empty must not poison
$script:TunnelBannerCacheAt = Get-Date
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
# Monkeypatch Get-TunnelBanner internals by overriding SshX to return good banner once
function SshX {
  param([Parameter(ValueFromRemainingArguments=$true)]$a)
  $cmd = ($a -join ' ')
  if($cmd -match 'nc -w 2'){ return 'SSH-2.0-OpenSSH_for_Windows_9.5' }
  if($cmd -match 'echo open'){ return 'open' }
  return ''
}
Clear-TunnelBannerCache
$b = Get-TunnelBanner
if($b -notmatch 'OpenSSH_for_Windows'){ throw "banner=$b" }
if(-not (Test-TunnelUp)){ throw 'Test-TunnelUp false after good banner' }
# Simulate miss then soft tcp path pieces
function SshX { param([Parameter(ValueFromRemainingArguments=$true)]$a)
  $cmd=($a -join ' ')
  if($cmd -match 'nc -w 2'){ return '' }
  if($cmd -match 'echo open|Connection refused'){ return 'open' }
  return ''
}
Clear-TunnelBannerCache
$b2 = Get-TunnelBanner
if($b2 -ne ''){ throw "expected empty got $b2" }
if($script:TunnelBannerCacheUp){ throw 'negative cached as up' }
if($script:TunnelBannerCacheAt){ throw 'negative cache timestamp set (poison)' }
Write-Output 'SMOKE_OK'
