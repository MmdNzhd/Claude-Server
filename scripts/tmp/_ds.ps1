$p='publish/deploy-client-bundles.ps1'
(Get-Content $p)[190..230] | ForEach-Object -Begin {$i=191} -Process { Write-Output ("{0}:{1}" -f $i, $_); $i++ }
