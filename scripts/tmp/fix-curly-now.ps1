$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$t=[IO.File]::ReadAllText($p)
$before=([regex]::Matches($t,'[\u201C\u201D\u2018\u2019\u2014\u2013]')).Count
$t2=$t -replace '[\u201C\u201D]','"' -replace '[\u2018\u2019]',"'" -replace '[\u2014\u2013]','-'
[IO.File]::WriteAllText($p,$t2)
$after=([regex]::Matches([IO.File]::ReadAllText($p),'[\u201C\u201D\u2018\u2019]')).Count
"curly_before=$before curly_after=$after"
# show fixed line context
Select-String -Path $p -Pattern 'KeyChar' | Select-Object -First 5 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
