$ErrorActionPreference = 'Continue'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')
$pw = Get-SepidzSudoPassword
$user = Get-SepidzSshUser
$hostIp = '192.168.250.70'
$target = "$user@$hostIp"
Write-Host "Using password auth only for $target (len=$($pw.Length))"

# Find tools
$tools = @{
  sshpass = @(
    'C:\Program Files\Git\usr\bin\sshpass.exe',
    'C:\Tools\sshpass.exe',
    "$env:USERPROFILE\bin\sshpass.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  plink = @(Get-Command plink -EA SilentlyContinue | Select-Object -Expand Source) + @('C:\Program Files\PuTTY\plink.exe') | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  python = (Get-Command python -EA SilentlyContinue | Select-Object -Expand Source)
  wsl = (Get-Command wsl -EA SilentlyContinue | Select-Object -Expand Source)
}
$tools.GetEnumerator() | ForEach-Object { Write-Host ("{0}={1}" -f $_.Key, $_.Value) }

function SshPw([string]$RemoteCmd) {
  if ($tools.sshpass) {
    $env:SSHPASS = $pw
    & $tools.sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 $target $RemoteCmd
    return $LASTEXITCODE
  }
  if ($tools.plink) {
    # echo y for host key
    echo y | & $tools.plink -ssh -pw $pw -batch $target $RemoteCmd
    return $LASTEXITCODE
  }
  if ($tools.wsl) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
    # write password to temp in wsl via env
    wsl -e bash -lc "command -v sshpass >/dev/null && export SSHPASS=\$(printf '%s' '$b64' | base64 -d) && sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=15 $target $(printf %q "$RemoteCmd")"
    return $LASTEXITCODE
  }
  # Pure .NET using Renci.SshNet if available, else install? try assemblies
  $asm = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match 'Renci.SshNet' }
  Write-Host 'No sshpass/plink/wsl sshpass — trying pip install paramiko quickly'
  pip install --quiet paramiko 2>$null
  $py = @'
import sys, base64
pw = base64.b64decode(sys.argv[1]).decode()
import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(sys.argv[2], username=sys.argv[3], password=pw, timeout=15, allow_agent=False, look_for_keys=False)
stdin, stdout, stderr = c.exec_command(sys.argv[4])
sys.stdout.write(stdout.read().decode())
sys.stderr.write(stderr.read().decode())
sys.exit(stdout.channel.recv_exit_status())
'@
  $tmp = Join-Path $env:TEMP 'sepidz_pw_ssh.py'
  [IO.File]::WriteAllText($tmp, $py)
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
  python $tmp $b64 $hostIp $user $RemoteCmd
  return $LASTEXITCODE
}

$ec = SshPw 'echo OK_PW; whoami; hostname; date'
Write-Host "probe_exit=$ec"
if ($ec -ne 0) { throw "password SSH failed exit=$ec" }

# Full deploy using password SSH/SCP wrappers
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$sepidDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$clientRoot = Join-Path $sepidDir.FullName 'claude-code'
$ver = (Get-Content (Join-Path $clientRoot 'windows\connect-version.txt') -Raw).Trim()
Write-Host "package=$($sepidDir.FullName) ver=$ver"

# Use deploy-client-bundles but we need password SSH. Patch approach: set GIT_SSH / or wrap ssh in PATH.
# Create temp bin with ssh/scp wrappers using sshpass
$bin = Join-Path $env:TEMP 'sepidz-ssh-wrap'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$sshWrap = Join-Path $bin 'ssh.cmd'
$scpWrap = Join-Path $bin 'scp.cmd'
if (-not $tools.sshpass) {
  # ensure paramiko path for wrappers is harder for scp; require sshpass
  # Try to get sshpass via chocolatey? Or use plink pscp
  if ($tools.plink) {
    @"
@echo off
REM plink-based ssh wrapper - not full ssh compat
"@ | Set-Content $sshWrap
    throw 'Need sshpass for scp wrapper; plink-only incomplete'
  }
  throw 'sshpass required for deploy wrappers'
}

$env:SSHPASS = $pw
@"
@echo off
set SSHPASS=$pw
"$($tools.sshpass)" -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=20 %*
"@ | Set-Content -Path $sshWrap -Encoding ASCII

@"
@echo off
set SSHPASS=$pw
"$($tools.sshpass)" -e scp -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=30 %*
"@ | Set-Content -Path $scpWrap -Encoding ASCII

$env:PATH = "$bin;" + $env:PATH
Write-Host "PATH wrap=$bin"

& (Join-Path (Resolve-Path 'publish').Path 'deploy-client-bundles.ps1') `
  -ProjectRoot (Resolve-Path '.').Path `
  -SepidClientRoot $clientRoot `
  -SepidServer $target `
  -DeploySmart:$false `
  -DeploySepidz:$true

Write-Host 'DEPLOY_DONE'
# verify
& $tools.sshpass -e ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $target "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; ls -la /usr/local/share/claude-client/connect-version.txt"
