Write-Output 'T1 hostname'
ssh -n -o BatchMode=yes -o ConnectTimeout=8 sepidz@192.168.250.70 hostname
Write-Output "E1=$LASTEXITCODE"
Write-Output 'T2 base64 plain'
ssh -n -o BatchMode=yes -o ConnectTimeout=8 sepidz@192.168.250.70 "echo cHJpbnRmIFBVU0hfT0tcbg== | base64 -d | bash"
Write-Output "E2=$LASTEXITCODE"
Write-Output 'T3 timeout wrap'
ssh -n -o BatchMode=yes -o ConnectTimeout=8 sepidz@192.168.250.70 "timeout 10 bash -lc 'echo cHJpbnRmIFBVU0hfT0tcbg== | base64 -d | bash'"
Write-Output "E3=$LASTEXITCODE"
Write-Output DONE
