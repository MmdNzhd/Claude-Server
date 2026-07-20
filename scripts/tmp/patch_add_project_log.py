from pathlib import Path
p = Path(r'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1')
c = p.read_text(encoding='utf-8')
c = c.replace(
    "function Add-Project {\n    Write-Host ''\n    Write-Host '    Add project' -ForegroundColor White\n    Write-Host ''\n",
    "function Add-Project {\n    Write-ConnectDecision 'project_menu' 'add_begin'\n    Write-Host ''\n    Write-Host '    Add project' -ForegroundColor White\n    Write-Host ''\n",
    1,
)
c = c.replace(
    "$nPath = (Read-Host '    Folder on your laptop (e.g. D:\\Smart)').Trim() -replace '\\\\','/'\n",
    "$nPath = (Read-ConnectPrompt '    Folder on your laptop (e.g. D:\\Smart)' -Tag 'ADD_PATH').Trim() -replace '\\\\','/'\n",
    1,
)
c = c.replace(
    '$d = (Read-Host "    Name [$nLbl]").Trim(); if ($d) { $nLbl = $d }\n',
    '$d = (Read-ConnectPrompt "    Name [$nLbl]" -Tag \'ADD_NAME\').Trim(); if ($d) { $nLbl = $d }\n    Write-ConnectDecision \'project_add\' ("id={0} label={1} path={2}" -f $nId, $nLbl, $nPath)\n',
    1,
)
c = c.replace(
    "$nUser = (Read-Host '    New server username (Enter to cancel)').Trim()\n",
    "$nUser = (Read-ConnectPrompt '    New server username (Enter to cancel)' -Tag 'CFG_USER').Trim()\n",
    1,
)
c = c.replace(
    '$fix = (Read-Host "    Username changed? Enter new username (or Enter to exit)").Trim()\n',
    '$fix = (Read-ConnectPrompt "    Username changed? Enter new username (or Enter to exit)" -Tag \'SSH_USER_FIX\').Trim()\n    Write-ConnectDecision \'ssh_username_fix\' $fix\n',
    1,
)
p.write_text(c, encoding='utf-8', newline='\n')
print('add-project extras OK')
