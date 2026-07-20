$c=Get-Content 'publish\deploy-client-bundles.ps1'
70..160 | ForEach-Object { '{0,4}|{1}' -f $_, $c[$_-1] }
Write-Output '==== call site 250-290 ===='
250..290 | ForEach-Object { '{0,4}|{1}' -f $_, $c[$_-1] }
