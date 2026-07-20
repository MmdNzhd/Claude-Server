from pathlib import Path
path = Path.cwd() / "publish" / "deploy-client-bundles.ps1"
c = path.read_text(encoding="utf-8-sig")

c = c.replace(
    "[Parameter(Mandatory)][string]$SmartClientRoot,\n    [Parameter(Mandatory)][string]$SepidClientRoot,",
    "[string]$SmartClientRoot = '',\n    [string]$SepidClientRoot = '',",
    1,
)

insert = """
if ($DeploySmart -and -not $SmartClientRoot) { throw 'SmartClientRoot is required when -DeploySmart is set' }
if ($DeploySepidz -and -not $SepidClientRoot) { throw 'SepidClientRoot is required when -DeploySepidz is set' }
"""
marker = "if (-not $PSBoundParameters.ContainsKey('SepidServer')) { $SepidServer = Get-SepidzServerTarget }"
c = c.replace(marker, marker + insert, 1)

c = c.replace(
    'Write-Host "Server deploy complete (Smart + Sepidz)." -ForegroundColor Green',
    "$labels = @($targets | ForEach-Object { $_.Label })\nWrite-Host (\"Server deploy complete ({0}).\" -f ($labels -join ' + ')) -ForegroundColor Green",
    1,
)

path.write_text(c, encoding="utf-8")
print('patched params and done message')
