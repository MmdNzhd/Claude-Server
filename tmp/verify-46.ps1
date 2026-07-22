$ErrorActionPreference='Continue'
$fail=0
function Ok($m){ Write-Host "PASS $m" }
function Bad($m){ Write-Host "FAIL $m"; $script:fail++ }
$root='D:\Smart\Claude-Code-Server\scripts\client'
$v=(Get-Content "$root\windows\connect-version.txt" -Raw).Trim()
if($v -eq '20260721.46'){ Ok "version $v" } else { Bad "version $v" }
foreach($pair in @(
  @("$root\windows\connect.ps1", "ConnectVersion = '20260721.46'"),
  @("$root\mac\connect.sh", "CONNECT_VERSION='20260721.46'"),
  @("$root\git-mode.ps1", 'Get-HttpProxyPort'),
  @("$root\git-mode.ps1", '19180'),
  @("$root\git-mode.ps1", 'XrayServerHttpPort'),
  @("$root\git-mode.ps1", 'missing_http'),
  @("$root\git-mode.ps1", '10809'),
  @("$root\git-mode.ps1", 'HttpProxyPort'),
  @("$root\git-mode.sh", 'HTTP_PROXY_PORT'),
  @("$root\git-mode.sh", '19180'),
  @("$root\git-mode.sh", 'missing_http'),
  @("$root\editor-launch.ps1", 'http://127.0.0.1:$HttpPort'),
  @("$root\editor-launch.sh", 'http://127.0.0.1:${http_port}'),
  @("$root\editor-launch.ps1", '--proxy-server=socks5://')
)) {
  if(Select-String -Path $pair[0] -Pattern ([regex]::Escape($pair[1])) -SimpleMatch -Quiet){ Ok ("has: "+$pair[1]) }
  elseif(Select-String -Path $pair[0] -Pattern $pair[1] -Quiet){ Ok ("has re: "+$pair[1]) }
  else { Bad ("missing in "+[IO.Path]::GetFileName($pair[0])+": "+$pair[1]) }
}
$el="$root\editor-launch.ps1"
$ne=@(Select-String -Path $el -Pattern 'elevated_non_elevated_launcher Start=false')
if($ne.Count -ge 1 -and ($ne[0].Line -match "'DEBUG'|`"DEBUG`"")){ Ok 'non_elevated Start=false is DEBUG' } else { Bad ("non_elevated log: "+$(if($ne){$ne[0].Line}else{'none'})) }
$call=@(Select-String -Path $el -Pattern 'Set-CursorProxySettings')
$call | ForEach-Object { Write-Host ("CALL L$($_.LineNumber): $($_.Line.Trim())") }
if(($call | Where-Object { $_.Line -match 'HttpPort' }).Count -ge 1){ Ok 'call site has HttpPort' } else { Bad 'call site missing HttpPort' }
$mcp='D:\Smart\Claude-Code-Server\scripts\server\cursor-mcp-template.json'
$j=Get-Content $mcp -Raw | ConvertFrom-Json
foreach($n in @('figma','context7')){
  $t=[string]$j.mcpServers.$n.type
  $u=[string]$j.mcpServers.$n.url
  if($t -eq 'http' -and $u -match '^https://'){ Ok "mcp $n type=$t" } else { Bad "mcp $n type=$t url=$u" }
}
Write-Host "FAILS=$fail"
if($fail -eq 0){ Write-Host 'VERIFY46_OK'; exit 0 } else { Write-Host 'VERIFY46_BAD'; exit 1 }
