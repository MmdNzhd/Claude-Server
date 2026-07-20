$ErrorActionPreference='Continue'
$clearFlag='0'; $preferEsc='frontend'; $lu='farzadb'; $portEsc='21006'; $modeEsc='off'
$remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
MODE='$modeEsc'
if [ "`$CLEAR" = "1" ]; then AM=
elif [ -n "`$PREFER" ]; then AM=`$PREFER
else AM=`$(echo backend)
fi
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\n' "`$CLEAR" "`$PREFER" "`$AM"
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
$tmp = Join-Path $env:TEMP 'pushconf-b64.txt'
Set-Content -LiteralPath $tmp -Value $b64 -Encoding ASCII -NoNewline
scp -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none $tmp sepidz@192.168.250.70:/tmp/pushconf-b64.txt
$out = ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "base64 -d </tmp/pushconf-b64.txt | bash; echo EXIT=\$?"
Write-Output $out
# Also simulate SshX wrap
function Escape-BashSingleQuoted([string]$Text) { return $Text -replace "'", "'\''" }
$remote = "echo $b64 | base64 -d | bash"
$escaped = Escape-BashSingleQuoted $remote
$remoteCmd = "timeout 45 bash -lc '$escaped'"
Write-Output ("CMDLEN=" + $remoteCmd.Length)
$out2 = ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 $remoteCmd
Write-Output "SSHX_STYLE=$out2"
Write-Output "SSHX_EXIT=$LASTEXITCODE"
