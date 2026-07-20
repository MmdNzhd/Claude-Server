$ErrorActionPreference = 'Stop'
. (Join-Path (Resolve-Path 'publish').Path 'Get-DeployCredentials.ps1')

$user = Get-SepidzSshUser
$hostIp = '192.168.250.70'
$target = '{0}@{1}' -f $user, $hostIp
$sudoPw = Get-SepidzSudoPassword
Write-Host ("target={0} user={1} hasSudo={2}" -f $target, $user, [bool]$sudoPw)

# Prefer IdentityFile without agent (agent refused)
$ids = @(
  "$env:USERPROFILE\.ssh\id_ed25519",
  "$env:USERPROFILE\.ssh\id_rsa",
  "$env:USERPROFILE\.ssh\sepidz",
  "$env:USERPROFILE\.ssh\id_ed25519_sepidz"
) | Where-Object { Test-Path $_ }

Write-Host 'identity files:'
$ids | ForEach-Object { Write-Host "  $_" }

function Invoke-SshNoAgent([string]$Target, [string]$Remote, [string]$IdFile = '') {
  $args = @('-n','-o','BatchMode=yes','-o','ConnectTimeout=12','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','-o','PreferredAuthentications=publickey')
  if ($IdFile) { $args += @('-i', $IdFile) }
  $args += @($Target, $Remote)
  & ssh @args 2>&1
  return $LASTEXITCODE
}

# Try each identity without agent
$worked = $null
foreach ($id in $ids) {
  Write-Host "try key $id"
  $out = Invoke-SshNoAgent -Target $target -Remote 'echo OK; whoami; hostname' -IdFile $id
  Write-Host (" exit={0}" -f $out)
  if ($out -eq 0) { $worked = $id; break }
}

# Also try smart@ with no agent
Write-Host 'try smart@ no-agent'
$out2 = Invoke-SshNoAgent -Target 'smart@192.168.250.70' -Remote 'echo OK; whoami' -IdFile $(if ($ids) { $ids[0] } else { '' })
Write-Host (" smart exit={0}" -f $out2)

# sshpass / plink availability
Write-Host ("sshpass={0}" -f [bool](Get-Command sshpass -EA SilentlyContinue))
Write-Host ("plink={0}" -f [bool](Get-Command plink -EA SilentlyContinue))
Write-Host ("wsl={0}" -f [bool](Get-Command wsl -EA SilentlyContinue))
Write-Host ("posix_sshpass=$(where.exe sshpass 2>$null)")

# If we have password, try sshpass via WSL or Git usr bin
$sshpass = $null
foreach ($c in @(
  'C:\Program Files\Git\usr\bin\sshpass.exe',
  'C:\Program Files (x86)\Git\usr\bin\sshpass.exe',
  (Get-Command sshpass -EA SilentlyContinue | Select-Object -ExpandProperty Source)
)) {
  if ($c -and (Test-Path $c)) { $sshpass = $c; break }
}
Write-Host ("sshpassPath={0}" -f $sshpass)

if ($sudoPw -and -not $worked) {
  # Use password for SSH login (same as sudo for sepidz ops)
  $env:SSHPASS = $sudoPw
  if ($sshpass) {
    Write-Host 'SSH with sshpass...'
    & $sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=12 $target 'echo OK_PW; whoami; hostname'
    Write-Host ("exit={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -eq 0) { $worked = 'password' }
  } elseif (Get-Command wsl -EA SilentlyContinue) {
    Write-Host 'SSH with wsl sshpass...'
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sudoPw))
    wsl -e bash -lc "export SSHPASS=\$(echo $b64 | base64 -d); sshpass -e ssh -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=12 $target 'echo OK_PW; whoami; hostname'"
    Write-Host ("exit={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -eq 0) { $worked = 'password-wsl' }
  } else {
    # PowerShell + Posh-SSH? or python paramiko
    Write-Host 'try python paramiko/pexpect style'
    $py = @'
import sys, base64
pw = base64.b64decode(sys.argv[1]).decode()
host = sys.argv[2]
user = sys.argv[3]
cmd = sys.argv[4]
try:
    import paramiko
except ImportError:
    print("NO_PARAMIKO"); sys.exit(2)
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(host, username=user, password=pw, timeout=12, allow_agent=False, look_for_keys=False)
stdin, stdout, stderr = c.exec_command(cmd)
print(stdout.read().decode())
print(stderr.read().decode(), file=sys.stderr)
sys.exit(stdout.channel.recv_exit_status())
'@
    $tmpPy = Join-Path $env:TEMP 'sepidz-ssh.py'
    Set-Content -Path $tmpPy -Value $py -Encoding UTF8
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sudoPw))
    python $tmpPy $b64 $hostIp $user 'echo OK_PY; whoami; hostname'
    Write-Host ("py exit={0}" -f $LASTEXITCODE)
    if ($LASTEXITCODE -eq 0) { $worked = 'paramiko' }
  }
}

Write-Host ("WORKED={0}" -f $worked)
