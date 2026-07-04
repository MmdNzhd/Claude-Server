param([string]$Path)
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
if (-not $errs -or $errs.Count -eq 0) { Write-Host 'OK parse'; exit 0 }
foreach ($err in $errs) {
    Write-Host ("L{0}: {1}" -f $err.Extent.StartLineNumber, $err.Message)
}
exit 1
