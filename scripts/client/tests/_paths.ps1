# Shared paths for client test scripts (dot-source from tests/*.ps1)
$script:TestsDir    = $PSScriptRoot
$script:ClientRoot   = Split-Path -Parent $TestsDir
$script:ScriptsRoot  = Split-Path -Parent $script:ClientRoot
$script:RepoRoot     = Split-Path -Parent $script:ScriptsRoot

function Get-ClientFile([string]$Rel) {
    Join-Path $script:ClientRoot ($Rel -replace '/', '\')
}

function Get-ServerFile([string]$Rel) {
    Join-Path $script:ScriptsRoot ($Rel -replace '/', '\')
}
