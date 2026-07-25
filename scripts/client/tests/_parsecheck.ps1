param([string]$Path)
try {
    $null = [scriptblock]::Create((Get-Content -Raw -LiteralPath $Path))
    Write-Host "PARSE OK: $Path"
    exit 0
} catch {
    Write-Host "PARSE FAIL: $Path -- $($_.Exception.Message)"
    exit 1
}
