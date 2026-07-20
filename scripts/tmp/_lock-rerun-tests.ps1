$ErrorActionPreference = 'Continue'
$root = (Get-Location).Path
Write-Output "=== pipeline ==="
& "$root\scripts\client\tests\test-connect-pipeline.ps1" *>&1 | Tee-Object -Variable pipeOut
$pipeEc = $LASTEXITCODE
Write-Output "PIPELINE_EC=$pipeEc"
Write-Output "=== git-mode-deep ==="
& "$root\scripts\client\tests\test-git-mode-deep.ps1" *>&1 | Tee-Object -Variable gitOut
$gitEc = $LASTEXITCODE
Write-Output "GITMODE_EC=$gitEc"

# Isolate curly assert
. "$root\scripts\client\tests\_paths.ps1"
$p = Get-ClientFile 'windows\connect.ps1'
$src = Get-Content $p -Raw
$curlyOk = ($src -notmatch '[\u201C\u201D\u2018\u2019]')
Write-Output "CURLY_ISOLATED_OK=$curlyOk path=$p len=$($src.Length)"

# Isolate folder-uri assert
$el = Get-Content (Get-ClientFile 'editor-launch.sh') -Raw
$folderBad = ($el -match 'folder-uri\*\).*return 0')
Write-Output "FOLDER_URI_LOOSE_MATCH=$folderBad"
# tighter bad pattern: return 0 immediately in folder-uri arm
$folderTightBad = ($el -match 'folder-uri\*\)\s*return 0')
Write-Output "FOLDER_URI_TIGHT_BAD=$folderTightBad"
