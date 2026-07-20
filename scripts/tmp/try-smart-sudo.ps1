# Probe sudo options for smart
ssh -o BatchMode=yes -o ConnectTimeout=12 smart@192.168.210.240 'sudo -n true 2>&1; echo exit_n=$?; sudo -l 2>&1 | head -40'
# Check for local smart password files
Get-ChildItem 'D:\Smart\Claude-Code-Server\publish' -Filter '*smart*local*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
Get-ChildItem 'D:\Smart\Claude-Code-Server\publish' -Filter '*deploy*.local*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
