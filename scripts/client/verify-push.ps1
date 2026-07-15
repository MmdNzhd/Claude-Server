ssh claude-server "which laptop-exec; grep -c resolve-w ~/.local/bin/laptop-exec; ~/.local/bin/laptop-exec test" 2>&1 | Select-Object -Last 10
