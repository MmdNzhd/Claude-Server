Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -match 'connect(-update)?\.ps1|install-client-bundle' } |
  Select-Object ProcessId, ParentProcessId, CreationDate,
    @{n='Age_s';e={ [int]((Get-Date) - $_.CreationDate).TotalSeconds }},
    @{n='Cmd';e={ $_.CommandLine }} |
  Sort-Object CreationDate |
  Format-List
