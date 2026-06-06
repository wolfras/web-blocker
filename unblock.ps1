# =============================================
# EMERGENCY UNBLOCK - Run as Administrator
# Removes ALL blocks from hosts file and firewall
# =============================================

# Auto-elevate to admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WEBSITE BLOCKER - FULL CLEANUP TOOL  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$totalFixed = 0

# ── 1. CLEAN HOSTS FILE ──────────────────────
Write-Host "[1/4] Cleaning hosts file..." -ForegroundColor Yellow
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

try {
    $content = Get-Content $hostsPath -Raw -ErrorAction Stop

    # Remove our blocker section (marked block)
    $before = $content
    $content = $content -replace "(?s)\r?\n?# == WEBSITE-BLOCKER-START ==.+?# == WEBSITE-BLOCKER-END ==\r?\n?", "`n"

    # Also remove any leftover 0.0.0.0 lines (from old script versions)
    $lines = $content -split "`r?`n"
    $cleaned = $lines | Where-Object { $_ -notmatch "^\s*0\.0\.0\.0\s+" }
    $content = ($cleaned -join "`n").Trim() + "`n"

    [System.IO.File]::WriteAllText($hostsPath, $content, [System.Text.Encoding]::ASCII)

    $removed = ($before -split "`n").Count - ($content -split "`n").Count
    Write-Host "   Hosts file cleaned. Removed approx $([Math]::Abs($removed)) lines." -ForegroundColor Green
    $totalFixed++
} catch {
    Write-Host "   ERROR reading hosts file: $_" -ForegroundColor Red
}

# ── 2. REMOVE WB-* FIREWALL RULES (new script) ──
Write-Host "[2/4] Removing WB-* firewall rules..." -ForegroundColor Yellow
try {
    $wbRules = netsh advfirewall firewall show rule name=all | Select-String "^Rule Name:\s+WB-"
    $wbCount = 0
    foreach ($r in $wbRules) {
        $name = ($r.Line -replace "^Rule Name:\s+").Trim()
        netsh advfirewall firewall delete rule name="$name" 2>$null | Out-Null
        $wbCount++
    }
    Write-Host "   Removed $wbCount WB-* firewall rule(s)." -ForegroundColor Green
    $totalFixed += $wbCount
} catch {
    Write-Host "   ERROR removing WB-* rules: $_" -ForegroundColor Red
}

# ── 3. REMOVE Block-* FIREWALL RULES (old script) ──
Write-Host "[3/4] Removing Block-* firewall rules (old script)..." -ForegroundColor Yellow
try {
    $blockRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Block-*" }
    $blockCount = 0
    foreach ($rule in $blockRules) {
        Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
        $blockCount++
    }
    Write-Host "   Removed $blockCount Block-* firewall rule(s)." -ForegroundColor Green
    $totalFixed += $blockCount
} catch {
    Write-Host "   ERROR removing Block-* rules: $_" -ForegroundColor Red
}

# ── 4. FLUSH DNS ─────────────────────────────
Write-Host "[4/4] Flushing DNS cache..." -ForegroundColor Yellow
try {
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    ipconfig /flushdns | Out-Null
    Write-Host "   DNS cache flushed." -ForegroundColor Green
} catch {
    Write-Host "   DNS flush failed (non-critical)." -ForegroundColor DarkYellow
}

# ── DONE ─────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DONE. Total items cleaned: $totalFixed" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All blocks have been removed." -ForegroundColor White
Write-Host "You can close this window and try accessing websites again." -ForegroundColor White
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")