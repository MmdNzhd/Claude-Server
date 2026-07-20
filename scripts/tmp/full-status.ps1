$ErrorActionPreference='Continue'
function Run-Ssh([string]$Target,[string]$Cmd){
  $args=@('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',$Target,$Cmd)
  $out=Join-Path $env:TEMP 'full-ssh-out.txt'; $err=Join-Path $env:TEMP 'full-ssh-err.txt'
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  [pscustomobject]@{ Exit=$p.ExitCode; Out=((Get-Content $out -Raw -EA SilentlyContinue) -replace '\s+$',''); Err=((Get-Content $err -Raw -EA SilentlyContinue) -replace '\s+$','') }
}
Write-Output '=== LOCAL VERSIONS ==='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect-version.txt'
(Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1' -Pattern "ConnectVersion\s*=" | Select-Object -First 1).Line.Trim()
(Select-String -Path 'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh' -Pattern 'CONNECT_VERSION=' | Select-Object -First 1).Line.Trim()
Write-Output '=== SEPIDZ BUNDLE ==='
$r=Run-Ssh 'claude-server-sepidz' @'
hostname
echo VER=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt)
ls -la /usr/local/share/claude-client/windows/connect.ps1 /usr/local/share/claude-client/mac/connect.sh /usr/local/share/claude-client/git-mode.ps1 /usr/local/share/claude-client/git-mode.sh 2>&1 | head -20
grep -n "IdentityAgent\|PUSH_CONF_RESULT\|useVk\|skip_duplicate\|SESSION_KEY ignore\|soft_fail count=.*\/6\|ORPHAN_TUNNEL: skip_current\|_action=\"\"" /usr/local/share/claude-client/windows/connect.ps1 /usr/local/share/claude-client/git-mode.ps1 /usr/local/share/claude-client/mac/connect.sh /usr/local/share/claude-client/mac/git-mode.sh 2>/dev/null | head -40
'@
"exit=$($r.Exit)"; $r.Out; if($r.Err){"ERR: $($r.Err)"}
Write-Output '=== SMART BUNDLE (must stay frozen) ==='
$r2=Run-Ssh 'claude-server' @'
hostname
echo VER=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt)
'@
"exit=$($r2.Exit)"; $r2.Out; if($r2.Err){"ERR: $($r2.Err)"}
Write-Output '=== KEY PATCH MARKERS (repo) ==='
$files=@(
 'scripts\client\windows\connect.ps1',
 'scripts\client\git-mode.ps1',
 'scripts\client\mac\connect.sh',
 'scripts\client\git-mode.sh',
 'scripts\client\connect-ui.ps1',
 'publish\deploy-client-bundles.ps1'
)
foreach($f in $files){
  $p="D:\Smart\Claude-Code-Server\$f"
  $hits=@(Select-String -Path $p -Pattern 'useVk|PUSH_CONF_RESULT|skip_duplicate|IdentityAgent=none|SESSION_KEY ignore|soft_fail count=.*/6|ORPHAN_TUNNEL: skip_current|_action=""|ActiveProjectId|PROJECT_MENU ignore|Keep durable local' -ErrorAction SilentlyContinue)
  "{0}: {1} markers" -f $f, $hits.Count
}
Write-Output '=== PUBLISH FOLDER ==='
Get-ChildItem "$env:USERPROFILE\Desktop\claude-publish" -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1 | ForEach-Object {
  $ver=Get-Content (Join-Path $_.FullName 'claude-code\windows\connect-version.txt') -EA SilentlyContinue
  "dir=$($_.Name) ver=$ver"
}
