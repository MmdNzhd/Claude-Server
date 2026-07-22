$ErrorActionPreference = 'Stop'
$p = 'scripts/client/connect-ui.ps1'
$t = [IO.File]::ReadAllText($p)
$bad = @'
function Test-ConnectRemoteLogNeedsRebuild {
    param(
        [int64],
        [int] -lt 0) { return  -eq 0 -and ) { return  -gt 0 -and  * 2)) { return  -gt ( }
    return  =  -or -not (Test-Path -LiteralPath  = [int64](Read-ConnectLogSyncWatermark -LogPath  = [int64]([System.IO.FileInfo]::new( -lt 0) {  -gt  }
        return ()
    } catch { return [int64]0 }
}

'@
if (-not $t.Contains($bad)) { throw 'corrupt block not found' }
$t = $t.Replace($bad, '')
[IO.File]::WriteAllText($p, $t)
Write-Host 'removed corrupt duplicate'
