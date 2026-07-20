$ErrorActionPreference='Stop'
$env:PYTHONUNBUFFERED='1'
# ensure smart-deploy.local.ps1 is gitignored
$gi = 'D:\Smart\Claude-Code-Server\.gitignore'
if (Test-Path $gi) {
  $raw = Get-Content $gi -Raw
  if ($raw -notmatch 'smart-deploy\.local\.ps1') {
    Add-Content $gi "`npublish/smart-deploy.local.ps1`npublish/*-deploy.local.ps1`n"
  }
}
python -u 'D:\Smart\Claude-Code-Server\scripts\tmp\finish-smart-with-pw.py'
exit $LASTEXITCODE
