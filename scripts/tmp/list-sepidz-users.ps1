$out = ssh -o BatchMode=yes -o ConnectTimeout=12 sepidz@192.168.250.70 'for u in /home/*; do basename "$u"; done | sort'
Write-Host 'Sepidz users (home dirs):' -ForegroundColor Cyan
$out | ForEach-Object { Write-Host "  $_" }
