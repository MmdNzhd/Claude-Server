$path='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.ps1'
$c=Get-Content -LiteralPath $path -Raw
$old=@'
    if ($HttpPort -gt 0) {
        $proxyUrl = "http://127.0.0.1:$HttpPort"
    } elseif ($SocksPort -gt 0) {
        $proxyUrl = "socks5://127.0.0.1:$SocksPort"
    } else {
        return $false
    }
'@
$new=@'
    if ($HttpPort -gt 0) {
        $proxyUrl = "http://127.0.0.1:$HttpPort"
    } elseif ($SocksPort -gt 0) {
        # Never write socks5 into settings.json: Cursor Node/MCP undici rejects it
        # ("Invalid URL protocol"). Chromium still uses --proxy-server=socks5 via CLI args.
        Write-EditorLaunchLog ("CURSOR_PROXY_SET: skip_settings no_http_leg socks={0} (CLI socks only)" -f $SocksPort) 'WARN'
        return $false
    } else {
        return $false
    }
'@
if($c -notlike "*$($old.Substring(0,40))*"){
  # try normalize CRLF
}
if($c.Contains($old)){
  $c2=$c.Replace($old,$new)
  [IO.File]::WriteAllText($path,$c2)
  Write-Host 'PS1_PATCHED'
} else {
  Write-Host 'PS1_ANCHOR_MISS'
  Select-String -Path $path -Pattern 'elseif \(\$SocksPort' -Context 2,6 | ForEach-Object { $_.ToString() }
}

# mac sh
$sh='D:\Smart\Claude-Code-Server\scripts\client\editor-launch.sh'
$sc=Get-Content -LiteralPath $sh -Raw
$oldSh=@'
    if [ -n "$http_port" ]; then
        proxy_url="http://127.0.0.1:${http_port}"
    elif [ -n "$socks_port" ]; then
        proxy_url="socks5://127.0.0.1:${socks_port}"
    else
        return 1
    fi
'@
$newSh=@'
    if [ -n "$http_port" ]; then
        proxy_url="http://127.0.0.1:${http_port}"
    elif [ -n "$socks_port" ]; then
        # Never write socks5 into settings.json (Node/MCP rejects it). CLI keeps socks5.
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CURSOR_PROXY_SET: skip_settings no_http_leg socks=${socks_port} (CLI socks only)" 'WARN'
        fi
        return 1
    else
        return 1
    fi
'@
if($sc.Contains($oldSh)){
  $sc2=$sc.Replace($oldSh,$newSh)
  # write unix newlines for sh
  $sc2=$sc2 -replace "`r`n","`n"
  [IO.File]::WriteAllText($sh,$sc2)
  Write-Host 'SH_PATCHED'
} else {
  Write-Host 'SH_ANCHOR_MISS'
}

# improve preserve log to include http
$c=Get-Content -LiteralPath $path -Raw
$c3=$c.Replace(
  'Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} (no soft-stop)" -f $script:SocksProxyPort) ''INFO''',
  'Write-EditorLaunchLog ("CURSOR_PROXY_SET: preserved_open_windows socks={0} http={1} (no soft-stop)" -f $script:SocksProxyPort, $httpProxyPort) ''INFO'''
)
if($c3 -ne $c){ [IO.File]::WriteAllText($path,$c3); Write-Host 'LOG_PATCHED' } else { Write-Host 'LOG_SAME' }

$tokens=$null;$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errs)
Write-Host ("PARSE_ERRS="+$errs.Count)
