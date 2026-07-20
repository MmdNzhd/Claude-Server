$path = 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1'
$c = Get-Content $path -Raw
$old = @'
                $sudoPw = ''
        if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw
'@
$new = @'
                $sudoPw = ''
        if ($target.Label -eq 'Sepidz') { $sudoPw = Get-SepidzSudoPassword }
        if ($target.Label -eq 'Smart') { $sudoPw = Get-SmartSudoPassword }
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw
'@
if ($c -notlike "*Get-SmartSudoPassword*") {
  if ($c.Contains($old)) {
    $c2 = $c.Replace($old, $new)
    Set-Content -Path $path -Value $c2 -Encoding UTF8
    Write-Host 'Patched deploy-client-bundles.ps1 for Smart sudo password'
  } else {
    Write-Host 'WARN: exact block not found; trying loose replace'
    $c2 = $c -replace "if \(\`$target\.Label -eq 'Sepidz'\) \{ \`$sudoPw = Get-SepidzSudoPassword \}", "if (`$target.Label -eq 'Sepidz') { `$sudoPw = Get-SepidzSudoPassword }`r`n        if (`$target.Label -eq 'Smart') { `$sudoPw = Get-SmartSudoPassword }"
    Set-Content -Path $path -Value $c2 -Encoding UTF8
    Write-Host 'Loose patch applied'
  }
} else {
  Write-Host 'Already patched'
}

# Ensure smart-deploy.local.ps1 is gitignored
$gi = 'D:\Smart\Claude-Code-Server\.gitignore'
$giC = Get-Content $gi -Raw
if ($giC -notmatch 'smart-deploy\.local\.ps1') {
  Add-Content $gi "`npublish/smart-deploy.local.ps1"
  Write-Host 'Added smart-deploy.local.ps1 to .gitignore'
}
Select-String -Path $path -Pattern 'Get-SmartSudoPassword|Get-SepidzSudoPassword'
