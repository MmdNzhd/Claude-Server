$ErrorActionPreference = 'Continue'
$repo = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$smart = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\connect.ps1'
$sepid = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect.ps1'

function Info($n,$p) {
  $i = Get-Item $p
  $bytes = [IO.File]::ReadAllBytes($p)
  $bom = if ($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF) { 'UTF8BOM' }
         elseif ($bytes.Length -ge 2 -and $bytes[0]-eq 0xFF -and $bytes[1]-eq 0xFE) { 'UTF16LE' }
         else { 'NOBOM' }
  $crlf = ([regex]::Matches([Text.Encoding]::UTF8.GetString($bytes), "`r`n")).Count
  $lfOnly = ([regex]::Matches([Text.Encoding]::UTF8.GetString($bytes), "(?<!`r)`n")).Count
  $hash = (Get-FileHash $p -Algorithm SHA256).Hash.Substring(0,16)
  Write-Output ("{0}: size={1} bom={2} crlf={3} lf={4} sha16={5}" -f $n,$i.Length,$bom,$crlf,$lfOnly,$hash)
}

Write-Output '=== CONNECT.PS1 ENCODING/EOL ==='
Info 'REPO' $repo
Info 'SMART_PKG' $smart
Info 'SEPID_PKG' $sepid

# Diff content ignoring line endings
$r = (Get-Content $repo -Raw) -replace "`r`n","`n" -replace "`r","`n"
$s = (Get-Content $smart -Raw) -replace "`r`n","`n" -replace "`r","`n"
$z = (Get-Content $sepid -Raw) -replace "`r`n","`n" -replace "`r","`n"
Write-Output ("repo_norm==smart_norm? " + ($r -eq $s))
Write-Output ("smart_norm has 210.240? " + ($s -match '192\.168\.210\.240'))
Write-Output ("smart_norm has 250.70? " + ($s -match '192\.168\.250\.70'))
Write-Output ("sepid_norm has 250.70? " + ($z -match '192\.168\.250\.70'))
Write-Output ("sepid_norm has 210.240? " + ($z -match '192\.168\.210\.240'))
# If repo!=smart after norm, show first diff snippet
if ($r -ne $s) {
  $rl = $r -split "`n"; $sl = $s -split "`n"
  $max = [Math]::Min($rl.Count,$sl.Count)
  $diffs = 0
  for ($i=0; $i -lt $max -and $diffs -lt 8; $i++) {
    if ($rl[$i] -ne $sl[$i]) {
      Write-Output ("DIFF line {0}:" -f ($i+1))
      Write-Output ("  REPO:  {0}" -f $rl[$i])
      Write-Output ("  SMART: {0}" -f $sl[$i])
      $diffs++
    }
  }
  Write-Output ("repo_lines={0} smart_lines={1}" -f $rl.Count,$sl.Count)
}

Write-Output ''
Write-Output '=== ZIP CONTENTS VERSION ==='
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($zipPath in @(
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717.zip'),
  (Join-Path $env:TEMP 'claude-client-bundle-smart.zip')
)) {
  if (-not (Test-Path $zipPath)) { Write-Output ("MISS $zipPath"); continue }
  Write-Output ("ZIP $zipPath")
}

# Stage from desktop package like deploy would - check server-side zip via scp download? instead extract version from published folder already done.
# Download remote zips versions via ssh + python file
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
function ZipVer($label,$target) {
  $cmd = 'python3 - <<"PY"
import zipfile, os, glob
paths=glob.glob(os.path.expanduser("~/claude-client-bundle-deploy/bundle.zip"))
print("zip_path", paths)
if not paths:
  raise SystemExit(0)
z=zipfile.ZipFile(paths[0])
names=[n for n in z.namelist() if n.endswith("connect-version.txt")]
print("entries", names)
for n in names:
  if n=="connect-version.txt" or (n.endswith("/connect-version.txt") and "mac/" not in n):
    print("ver", z.read(n).decode().strip().replace("\r",""), "from", n)
PY'
  $a=@('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=12',$target,$cmd)
  $o=Join-Path $env:TEMP "zipver-$label.out"
  $p=Start-Process ssh -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError (Join-Path $env:TEMP "zipver-$label.err")
  [void]$p.WaitForExit(20000)
  Write-Output "--- remote zip $label ---"
  Get-Content $o -EA SilentlyContinue
}
ZipVer 'SMART' 'smart@192.168.210.240'
ZipVer 'SEPIDZ' 'sepidz@192.168.250.70'

Write-Output ''
Write-Output '=== SERVER vs PKG SHA MATCH ==='
# From previous: smart editor 254861E..., connect.ps1 13012B2A matches SMART_PKG
$pkgEl = (Get-FileHash (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\editor-launch.ps1') -Algorithm SHA256).Hash.Substring(0,16)
$pkgCp = (Get-FileHash (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260717\windows\connect.ps1') -Algorithm SHA256).Hash.Substring(0,16)
$sepEl = (Get-FileHash (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\editor-launch.ps1') -Algorithm SHA256).Hash.Substring(0,16)
$sepCp = (Get-FileHash (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260717\claude-code\windows\connect.ps1') -Algorithm SHA256).Hash.Substring(0,16)
Write-Output ("SMART_PKG editor={0} connect.ps1={1}" -f $pkgEl,$pkgCp)
Write-Output ("SEPID_PKG editor={0} connect.ps1={1}" -f $sepEl,$sepCp)
Write-Output 'Expected server SMART: editor=254861e2409ff71a connect=13012b2a3e40947c'
Write-Output 'Expected server SEPID: editor=254861e2409ff71a connect=af32769105952aaa'
Write-Output ("SMART editor match? " + ($pkgEl -eq '254861E2409FF71A'))
Write-Output ("SMART connect match? " + ($pkgCp -eq '13012B2A3E40947C'))
Write-Output ("SEPID editor match? " + ($sepEl -eq '254861E2409FF71A'))
Write-Output ("SEPID connect match? " + ($sepCp -eq 'AF32769105952AAA'))

Write-Output ''
Write-Output '=== FALSE-OK PATH DETAIL ==='
# Reconstruct: if sudo fails but remoteVer exists (old), script still OK
$dep = 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
$lines = Get-Content $dep
for ($i=175; $i -le 225; $i++) {
  if ($i -ge 1 -and $i -le $lines.Count) {
    Write-Output ("{0,4}| {1}" -f $i, $lines[$i-1])
  }
}
