$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfgPath = 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1'
Write-Output "cfg_exists=$(Test-Path $cfgPath)"
if (Test-Path $cfgPath) {
  $raw = Get-Content $cfgPath -Raw
  Write-Output "has_sudo_pw=$($raw -match 'SepidzSudoPassword\s*=\s*''[^'']+''')"
  # also try double-quote style
  if ($raw -match "SepidzSudoPassword\s*=\s*'([^']*)'") {
    Write-Output "pw_style=single_quote pw_len=$($Matches[1].Length)"
  } elseif ($raw -match 'SepidzSudoPassword\s*=\s*"([^"]*)"') {
    Write-Output "pw_style=double_quote pw_len=$($Matches[1].Length)"
  } else {
    Write-Output 'pw_style=NOT_FOUND'
    Select-String -Path $cfgPath -Pattern 'Sudo|Password|Sepidz' | ForEach-Object {
      $l = $_.Line
      if ($l -match '(?i)pass') { $l = ($l -replace "(')[^']*(')", '${1}***${2}') -replace '(")[^"]*(")', '${1}***${2}' }
      $l
    }
  }
}

$remote = @'
#!/bin/bash
echo HOST=$(hostname)
echo WHO=$(whoami)
echo "=== passwd ==="
getent passwd | awk -F: '$3>=1000 {print $1 "|" $5 "|" $6}'
echo "=== sepidz logs dir ==="
ls -la /home/sepidz/.claude/logs 2>&1 | head -20
echo "=== try list others without sudo ==="
for u in alit aminb designer farzadb hosseinb hosseinm nimaz smart zahrak sepidz; do
  d=/home/$u/.claude/logs
  if [ -d "$d" ]; then
    n=$(ls "$d"/connect-*.log 2>/dev/null | wc -l)
    echo "OK $u count=$n"
    ls -lt "$d"/connect-*.log 2>/dev/null | head -2
  elif [ -d /home/$u ]; then
    echo "DENY_OR_EMPTY $u home_ok=$(test -x /home/$u && echo y || echo n)"
  else
    echo "NOHOME $u"
  fi
done
'@

$tmp = Join-Path $env:TEMP 'sepidz-azin-probe.sh'
Set-Content -Path $tmp -Value $remote -Encoding ASCII
scp -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=15 -q $tmp "${target}:/tmp/sepidz-azin-probe.sh"
Write-Output "scp_exit=$LASTEXITCODE"
ssh -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=20 $target 'bash /tmp/sepidz-azin-probe.sh'
Write-Output "ssh_exit=$LASTEXITCODE"
