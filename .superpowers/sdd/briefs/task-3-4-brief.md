# Combined Task 3+4 brief (same hotspot: connect.ps1 - serialize)

## Task 3
### Task 3: Defer tunnel+sidecar until after project pick (P0)

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (remove/gate line ~1849; keep ~1996)
- Modify: `scripts/client/tests/test-connect-pipeline.ps1` (line ~46 assertion)
- Modify: `scripts/client/tests/test-git-mode-deep.ps1` (~234 if asserts pre-warm)
- Optional docs: `docs/client-connect.md` one sentence Mac parity

**Interfaces:**
- Consumes: `$Alias`, `$sshCfg`, post-pick `$script:SessionBgTunnel`
- Produces: no `Initialize-SessionBgTunnel` between Ready and `project_menu_shown`; first call on project pick path

**Write-set:** `connect.ps1` + tests (serialize vs Task 4 if both touch connect.ps1 - **merge Tasks 3+4 into one wave serialized on connect.ps1**)

- [ ] **Step 1: RED** - flip pipeline test expectation:

```powershell
# test-connect-pipeline.ps1
Assert ($src -match 'Initialize-SessionBgTunnel') "$rel still defines/uses session bg tunnel"
# Replace pre-warm-after-Ready assert with:
Assert ($src -notmatch '(?s)Mark-BootstrapDone.*?Initialize-SessionBgTunnel.*?menuLoop') `
  "$rel must not pre-warm tunnel between Ready and menuLoop"
# Or simpler structural: Ready block must not call Initialize-SessionBgTunnel before :menuLoop
```

Write a precise regex that matches today's buggy order (Ready -> Ensure -> Initialize-SessionBgTunnel -> menuLoop) and fails when that order remains.

- [ ] **Step 2: Run pipeline test - expect FAIL on new assert once written against desired contract...**  
  Actually: write assert for **desired** contract; run against current tree -> FAIL; then implement.

- [ ] **Step 3: GREEN** - delete or comment-remove:

```powershell
# REMOVE from pre-menu boot (connect.ps1 ~1849):
# $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

# KEEP post-pick (~1996) and recovery/M-key sites.
```

Ensure `$script:SessionBgTunnel = $null` remains so post-pick path always starts tunnel.

- [ ] **Step 4: Run** `test-connect-pipeline.ps1` + `test-git-mode-deep.ps1` - PASS

- [ ] **Step 5: Commit** (if authorized)

```bash
git commit -m "perf(connect): defer reverse tunnel until after project pick"
```

---




## Task 4
### Task 4: Remove Ensure#2 + session firewall cache (P1)

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (`Test-LaptopSshReady` ~629-668, Ensure#1 ~858, Ensure#2 ~1833-1843)
- Modify: `scripts/client/tests/test-live-ssh-ready.ps1` and/or `test-hard-multi-agent-regressions.ps1` if they require Ensure#2 / `FAIL LAPTOP_SSH_BOOT` at boot

**Interfaces:**
- Consumes: Ensure#1 result in `Initialize-ServerSession`
- Produces: `$script:LaptopFirewallOk = $true` on Ensure#1 success; session cache skip for `Get-NetFirewallRule`; no Ensure#2 before menu

**Write-set:** `connect.ps1` - **same hotspot as Task 3 -> execute in same Worker after Task 3 or single Worker owns both**

- [ ] **Step 1: RED** - test that source has at most one `Ensure-LaptopSshReady` call between Server setup and `:menuLoop` (or that Ready block does not call it).

- [ ] **Step 2: Run - FAIL**

- [ ] **Step 3: GREEN**

```powershell
# In Initialize-ServerSession after Ensure#1 success (~858):
$script:LaptopFirewallOk = $true

# In Test-LaptopSshReady: if $script:LaptopFirewallCheckedOk -eq $true, skip Get-NetFirewallRule

# Remove Ensure#2 block (~1833-1843) entirely (or no-op if LaptopFirewallOk already true - prefer remove).
```

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit** (if authorized)

```bash
git commit -m "perf(connect): drop duplicate laptop SSH ensure before menu"
```

---



