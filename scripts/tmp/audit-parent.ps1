Get-CimInstance Win32_Process -Filter "ProcessId=32368" | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List
Get-CimInstance Win32_Process -Filter "ProcessId=39648" | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List
Get-CimInstance Win32_Process -Filter "ProcessId=59592" | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List
