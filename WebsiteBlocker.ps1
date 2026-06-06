# =============================================
# WEBSITE BLOCKER - OPTIMIZED v2.0
# Dual-method: HOSTS file (instant) + Firewall
# =============================================

# Auto-elevate to admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$HOSTS_PATH   = "$env:SystemRoot\System32\drivers\etc\hosts"
$MARKER_START = "# == WEBSITE-BLOCKER-START =="
$MARKER_END   = "# == WEBSITE-BLOCKER-END =="

# ---------------------------------------------
# CORE BLOCKING FUNCTIONS
# ---------------------------------------------

function Get-BlockedDomains {
    $content = Get-Content $HOSTS_PATH -Raw -ErrorAction SilentlyContinue
    if ($content -match "(?s)$MARKER_START(.+?)$MARKER_END") {
        return ($Matches[1].Trim() -split "`n" |
            Where-Object { $_ -match "^\s*0\.0\.0\.0\s+" } |
            ForEach-Object { ($_ -split "\s+")[1].Trim() } |
            Where-Object { $_ -ne "" })
    }
    return @()
}

function Block-Domains {
    param([string[]]$Domains, [bool]$UseFirewall, [bool]$BlockWWW)

    $newDomains = [System.Collections.Generic.List[string]]::new()
    $existing   = Get-BlockedDomains

    foreach ($d in $Domains) {
        $d = $d.Trim().ToLower() -replace "^https?://" -replace "/$"
        if ($d -eq "") { continue }
        if ($existing -notcontains $d)          { [void]$newDomains.Add($d) }
        if ($BlockWWW -and $d -notmatch "^www\.") {
            $www = "www.$d"
            if ($existing -notcontains $www)    { [void]$newDomains.Add($www) }
        }
    }

    if ($newDomains.Count -eq 0) { return 0 }

    # -- HOSTS FILE (primary, instant) ----------
    $content = Get-Content $HOSTS_PATH -Raw -ErrorAction SilentlyContinue
    if (-not $content) { $content = "" }

    $newLines = $newDomains | ForEach-Object { "0.0.0.0 $_" }

    if ($content -match "(?s)$MARKER_START(.+?)$MARKER_END") {
        $block       = $Matches[0]
        $innerLines  = ($block -split "`n" | Where-Object { $_ -notmatch $MARKER_START -and $_ -notmatch $MARKER_END })
        $merged      = ($innerLines + $newLines) -join "`n"
        $newBlock    = "$MARKER_START`n$merged`n$MARKER_END"
        $content     = $content -replace "(?s)$([regex]::Escape($MARKER_START))(.+?)$([regex]::Escape($MARKER_END))", $newBlock
    } else {
        $content = $content.TrimEnd() + "`n`n$MARKER_START`n" + ($newLines -join "`n") + "`n$MARKER_END`n"
    }

    [System.IO.File]::WriteAllText($HOSTS_PATH, $content, [System.Text.Encoding]::ASCII)

    # -- FIREWALL (optional, via netsh - fast) --
    if ($UseFirewall) {
        foreach ($d in $newDomains) {
            $name = "WB-$d"
            # netsh is far faster than New-NetFirewallRule
            netsh advfirewall firewall add rule name="$name" dir=out action=block remoteip=any protocol=any remoteport=any program=any localport=any 2>$null | Out-Null
        }
    }

    # Flush DNS cache
    Clear-DnsClientCache -ErrorAction SilentlyContinue

    return $newDomains.Count
}

function Unblock-AllDomains {
    # -- HOSTS FILE -----------------------------
    $content = Get-Content $HOSTS_PATH -Raw -ErrorAction SilentlyContinue
    if ($content -match "(?s)$([regex]::Escape($MARKER_START)).+?$([regex]::Escape($MARKER_END))") {
        $content = $content -replace "(?s)\r?\n?$([regex]::Escape($MARKER_START)).+?$([regex]::Escape($MARKER_END))\r?\n?", "`n"
        [System.IO.File]::WriteAllText($HOSTS_PATH, $content.Trim() + "`n", [System.Text.Encoding]::ASCII)
    }

    # -- FIREWALL - delete only WB-* rules ------
    $rules = netsh advfirewall firewall show rule name=all | Select-String "^Rule Name:\s+WB-"
    $count = 0
    foreach ($r in $rules) {
        $n = ($r.Line -replace "^Rule Name:\s+").Trim()
        netsh advfirewall firewall delete rule name="$n" 2>$null | Out-Null
        $count++
    }

    Clear-DnsClientCache -ErrorAction SilentlyContinue
    return $count
}

function Unblock-SelectedDomains {
    param([string[]]$Domains)

    $content = Get-Content $HOSTS_PATH -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return 0 }

    $removed = 0
    foreach ($d in $Domains) {
        $escaped = [regex]::Escape($d)
        if ($content -match "0\.0\.0\.0 $escaped") {
            $content = $content -replace "\r?\n?0\.0\.0\.0 $escaped\b[^\r\n]*", ""
            netsh advfirewall firewall delete rule name="WB-$d" 2>$null | Out-Null
            $removed++
        }
    }

    # Clean up empty marker block
    $content = $content -replace "(?s)$([regex]::Escape($MARKER_START))\s*$([regex]::Escape($MARKER_END))", ""
    [System.IO.File]::WriteAllText($HOSTS_PATH, $content, [System.Text.Encoding]::ASCII)

    Clear-DnsClientCache -ErrorAction SilentlyContinue
    return $removed
}

# ---------------------------------------------
# COLOR PALETTE
# ---------------------------------------------
$C = @{
    BG         = [System.Drawing.Color]::FromArgb(12,  12,  18 )
    Surface    = [System.Drawing.Color]::FromArgb(22,  22,  32 )
    Card       = [System.Drawing.Color]::FromArgb(28,  28,  42 )
    Border     = [System.Drawing.Color]::FromArgb(45,  45,  65 )
    Accent     = [System.Drawing.Color]::FromArgb(99,  102, 241)   # Indigo
    AccentHov  = [System.Drawing.Color]::FromArgb(129, 132, 255)
    Danger     = [System.Drawing.Color]::FromArgb(239, 68,  68 )
    DangerHov  = [System.Drawing.Color]::FromArgb(255, 90,  90 )
    Success    = [System.Drawing.Color]::FromArgb(34,  197, 94 )
    Muted      = [System.Drawing.Color]::FromArgb(110, 110, 140)
    Text       = [System.Drawing.Color]::FromArgb(230, 230, 245)
    TextDim    = [System.Drawing.Color]::FromArgb(140, 140, 165)
    Input      = [System.Drawing.Color]::FromArgb(18,  18,  28 )
    Yellow     = [System.Drawing.Color]::FromArgb(250, 204, 21 )
    White      = [System.Drawing.Color]::White
}

# ---------------------------------------------
# FORM
# ---------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.Text            = "Website Blocker  v2"
$Form.Size            = New-Object System.Drawing.Size(700, 620)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.BackColor       = $C.BG
$Form.ForeColor       = $C.Text
$Form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
$Form.DoubleBuffered  = $true

# -- HEADER ----------------------------------
$Header = New-Object System.Windows.Forms.Panel
$Header.Dock      = "Top"
$Header.Height    = 64
$Header.BackColor = $C.Surface
$Form.Controls.Add($Header)

$LogoBox = New-Object System.Windows.Forms.PictureBox
$LogoBox.Location  = New-Object System.Drawing.Point(20, 16)
$LogoBox.Size      = New-Object System.Drawing.Size(32, 32)
$LogoBox.BackColor = [System.Drawing.Color]::Transparent
$Header.Controls.Add($LogoBox)

# Draw shield icon on PictureBox
$LogoBox.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $pts = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(16,2),
        [System.Drawing.PointF]::new(30,8),
        [System.Drawing.PointF]::new(30,18),
        [System.Drawing.PointF]::new(16,30),
        [System.Drawing.PointF]::new(2,18),
        [System.Drawing.PointF]::new(2,8)
    )
    $brush = New-Object System.Drawing.SolidBrush($C.Accent)
    $g.FillPolygon($brush, $pts)
    $brush.Dispose()
    $pen = New-Object System.Drawing.Pen($C.White, 2)
    $g.DrawLine($pen, 10, 16, 14, 21)
    $g.DrawLine($pen, 14, 21, 22, 11)
    $pen.Dispose()
})

$TitleLbl = New-Object System.Windows.Forms.Label
$TitleLbl.Location  = New-Object System.Drawing.Point(62, 12)
$TitleLbl.Size      = New-Object System.Drawing.Size(300, 22)
$TitleLbl.Text      = "WEBSITE BLOCKER"
$TitleLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
$TitleLbl.ForeColor = $C.Text
$Header.Controls.Add($TitleLbl)

$SubLbl = New-Object System.Windows.Forms.Label
$SubLbl.Location  = New-Object System.Drawing.Point(63, 35)
$SubLbl.Size      = New-Object System.Drawing.Size(350, 16)
$SubLbl.Text      = "Hosts-file blocking  -  Instant  -  No restart needed"
$SubLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$SubLbl.ForeColor = $C.Muted
$Header.Controls.Add($SubLbl)

# Active-count badge
$BadgePanel = New-Object System.Windows.Forms.Panel
$BadgePanel.Location  = New-Object System.Drawing.Point(580, 16)
$BadgePanel.Size      = New-Object System.Drawing.Size(92, 32)
$BadgePanel.BackColor = $C.Card
$Header.Controls.Add($BadgePanel)

$BadgeNum = New-Object System.Windows.Forms.Label
$BadgeNum.Location  = New-Object System.Drawing.Point(8, 4)
$BadgeNum.Size      = New-Object System.Drawing.Size(40, 24)
$BadgeNum.Text      = "0"
$BadgeNum.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13, [System.Drawing.FontStyle]::Bold)
$BadgeNum.ForeColor = $C.Accent
$BadgeNum.TextAlign = "MiddleRight"
$BadgePanel.Controls.Add($BadgeNum)

$BadgeTxt = New-Object System.Windows.Forms.Label
$BadgeTxt.Location  = New-Object System.Drawing.Point(50, 10)
$BadgeTxt.Size      = New-Object System.Drawing.Size(36, 14)
$BadgeTxt.Text      = "active"
$BadgeTxt.Font      = New-Object System.Drawing.Font("Segoe UI", 7)
$BadgeTxt.ForeColor = $C.Muted
$BadgePanel.Controls.Add($BadgeTxt)

function Update-Badge {
    $n = @(Get-BlockedDomains).Count
    $BadgeNum.Text      = "$n"
    $BadgeNum.ForeColor = if ($n -gt 0) { $C.Accent } else { $C.Muted }
}

# -- LEFT PANEL: Input ------------------------
$LeftPanel = New-Object System.Windows.Forms.Panel
$LeftPanel.Location  = New-Object System.Drawing.Point(16, 80)
$LeftPanel.Size      = New-Object System.Drawing.Size(410, 490)
$LeftPanel.BackColor = $C.BG
$Form.Controls.Add($LeftPanel)

# Input card
$InputCard = New-Object System.Windows.Forms.Panel
$InputCard.Location  = New-Object System.Drawing.Point(0, 0)
$InputCard.Size      = New-Object System.Drawing.Size(410, 330)
$InputCard.BackColor = $C.Card
$LeftPanel.Controls.Add($InputCard)

$InputLbl = New-Object System.Windows.Forms.Label
$InputLbl.Location  = New-Object System.Drawing.Point(14, 12)
$InputLbl.Size      = New-Object System.Drawing.Size(382, 18)
$InputLbl.Text      = "DOMAINS TO BLOCK"
$InputLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$InputLbl.ForeColor = $C.Muted
$InputCard.Controls.Add($InputLbl)

$HintLbl = New-Object System.Windows.Forms.Label
$HintLbl.Location  = New-Object System.Drawing.Point(14, 30)
$HintLbl.Size      = New-Object System.Drawing.Size(382, 15)
$HintLbl.Text      = "One domain per line   -   e.g. facebook.com"
$HintLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$HintLbl.ForeColor = $C.Muted
$InputCard.Controls.Add($HintLbl)

$DomainBox = New-Object System.Windows.Forms.TextBox
$DomainBox.Location    = New-Object System.Drawing.Point(14, 52)
$DomainBox.Size        = New-Object System.Drawing.Size(382, 210)
$DomainBox.Multiline   = $true
$DomainBox.ScrollBars  = "Vertical"
$DomainBox.Font        = New-Object System.Drawing.Font("Cascadia Mono", 10)
$DomainBox.BackColor   = $C.Input
$DomainBox.ForeColor   = [System.Drawing.Color]::FromArgb(180, 220, 255)
$DomainBox.BorderStyle = "FixedSingle"
$InputCard.Controls.Add($DomainBox)

# Quick-add strip
$QuickLbl = New-Object System.Windows.Forms.Label
$QuickLbl.Location  = New-Object System.Drawing.Point(14, 270)
$QuickLbl.Size      = New-Object System.Drawing.Size(80, 20)
$QuickLbl.Text      = "Quick add:"
$QuickLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$QuickLbl.ForeColor = $C.Muted
$InputCard.Controls.Add($QuickLbl)

function New-QuickBtn($label, $domain, $x) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location  = New-Object System.Drawing.Point($x, 266)
    $b.Size      = New-Object System.Drawing.Size(65, 22)
    $b.Text      = $label
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize     = 1
    $b.FlatAppearance.BorderColor    = $C.Border
    $b.BackColor = $C.Surface
    $b.ForeColor = $C.TextDim
    $b.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $b.Tag       = $domain
    $b.Add_Click({
        $cur = $DomainBox.Text.TrimEnd()
        $DomainBox.Text = if ($cur) { "$cur`r`n$($this.Tag)" } else { $this.Tag }
        $DomainBox.SelectionStart = $DomainBox.Text.Length
    })
    $InputCard.Controls.Add($b)
}
New-QuickBtn "YouTube"   "youtube.com"   100
New-QuickBtn "TikTok"    "tiktok.com"    170
New-QuickBtn "Reddit"    "reddit.com"    240
New-QuickBtn "Twitter"   "twitter.com"   310

# Options card
$OptCard = New-Object System.Windows.Forms.Panel
$OptCard.Location  = New-Object System.Drawing.Point(0, 342)
$OptCard.Size      = New-Object System.Drawing.Size(410, 80)
$OptCard.BackColor = $C.Card
$LeftPanel.Controls.Add($OptCard)

$OptLbl = New-Object System.Windows.Forms.Label
$OptLbl.Location  = New-Object System.Drawing.Point(14, 10)
$OptLbl.Size      = New-Object System.Drawing.Size(200, 16)
$OptLbl.Text      = "OPTIONS"
$OptLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$OptLbl.ForeColor = $C.Muted
$OptCard.Controls.Add($OptLbl)

$WwwCheck = New-Object System.Windows.Forms.CheckBox
$WwwCheck.Location  = New-Object System.Drawing.Point(14, 30)
$WwwCheck.Size      = New-Object System.Drawing.Size(180, 22)
$WwwCheck.Text      = "Also block www. prefix"
$WwwCheck.Checked   = $true
$WwwCheck.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$WwwCheck.ForeColor = $C.Text
$OptCard.Controls.Add($WwwCheck)

$FwCheck = New-Object System.Windows.Forms.CheckBox
$FwCheck.Location  = New-Object System.Drawing.Point(210, 30)
$FwCheck.Size      = New-Object System.Drawing.Size(190, 22)
$FwCheck.Text      = "Firewall rule (extra layer)"
$FwCheck.Checked   = $false
$FwCheck.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$FwCheck.ForeColor = $C.Text
$OptCard.Controls.Add($FwCheck)

# Block button
$BlockBtn = New-Object System.Windows.Forms.Button
$BlockBtn.Location  = New-Object System.Drawing.Point(0, 438)
$BlockBtn.Size      = New-Object System.Drawing.Size(410, 44)
$BlockBtn.Text      = "  BLOCK WEBSITES"
$BlockBtn.FlatStyle = "Flat"
$BlockBtn.FlatAppearance.BorderSize = 0
$BlockBtn.BackColor = $C.Accent
$BlockBtn.ForeColor = $C.White
$BlockBtn.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 11, [System.Drawing.FontStyle]::Bold)
$BlockBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$LeftPanel.Controls.Add($BlockBtn)

$BlockBtn.Add_MouseEnter({ $BlockBtn.BackColor = $C.AccentHov })
$BlockBtn.Add_MouseLeave({ $BlockBtn.BackColor = $C.Accent })

# -- RIGHT PANEL: Active blocks ---------------
$RightPanel = New-Object System.Windows.Forms.Panel
$RightPanel.Location  = New-Object System.Drawing.Point(442, 80)
$RightPanel.Size      = New-Object System.Drawing.Size(242, 490)
$RightPanel.BackColor = $C.BG
$Form.Controls.Add($RightPanel)

$ListCard = New-Object System.Windows.Forms.Panel
$ListCard.Location  = New-Object System.Drawing.Point(0, 0)
$ListCard.Size      = New-Object System.Drawing.Size(242, 380)
$ListCard.BackColor = $C.Card
$RightPanel.Controls.Add($ListCard)

$ListHdr = New-Object System.Windows.Forms.Label
$ListHdr.Location  = New-Object System.Drawing.Point(12, 12)
$ListHdr.Size      = New-Object System.Drawing.Size(218, 16)
$ListHdr.Text      = "ACTIVE BLOCKS"
$ListHdr.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$ListHdr.ForeColor = $C.Muted
$ListCard.Controls.Add($ListHdr)

$ActiveList = New-Object System.Windows.Forms.ListBox
$ActiveList.Location           = New-Object System.Drawing.Point(12, 34)
$ActiveList.Size               = New-Object System.Drawing.Size(218, 300)
$ActiveList.BackColor          = $C.Input
$ActiveList.ForeColor          = [System.Drawing.Color]::FromArgb(180, 220, 180)
$ActiveList.Font               = New-Object System.Drawing.Font("Cascadia Mono", 8.5)
$ActiveList.BorderStyle        = "None"
$ActiveList.SelectionMode      = "MultiExtended"
$ActiveList.IntegralHeight     = $false
$ListCard.Controls.Add($ActiveList)

function Refresh-List {
    $ActiveList.BeginUpdate()
    $ActiveList.Items.Clear()
    Get-BlockedDomains | Sort-Object | ForEach-Object { [void]$ActiveList.Items.Add($_) }
    $ActiveList.EndUpdate()
    Update-Badge
}

# Remove selected
$RemoveSelBtn = New-Object System.Windows.Forms.Button
$RemoveSelBtn.Location  = New-Object System.Drawing.Point(12, 344)
$RemoveSelBtn.Size      = New-Object System.Drawing.Size(218, 28)
$RemoveSelBtn.Text      = "Remove Selected"
$RemoveSelBtn.FlatStyle = "Flat"
$RemoveSelBtn.FlatAppearance.BorderSize  = 1
$RemoveSelBtn.FlatAppearance.BorderColor = $C.Border
$RemoveSelBtn.BackColor = $C.Surface
$RemoveSelBtn.ForeColor = $C.TextDim
$RemoveSelBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$RemoveSelBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$ListCard.Controls.Add($RemoveSelBtn)

# Unblock all
$UnblockAllBtn = New-Object System.Windows.Forms.Button
$UnblockAllBtn.Location  = New-Object System.Drawing.Point(0, 392)
$UnblockAllBtn.Size      = New-Object System.Drawing.Size(242, 44)
$UnblockAllBtn.Text      = "UNBLOCK ALL"
$UnblockAllBtn.FlatStyle = "Flat"
$UnblockAllBtn.FlatAppearance.BorderSize = 0
$UnblockAllBtn.BackColor = $C.Danger
$UnblockAllBtn.ForeColor = $C.White
$UnblockAllBtn.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$UnblockAllBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$RightPanel.Controls.Add($UnblockAllBtn)

$UnblockAllBtn.Add_MouseEnter({ $UnblockAllBtn.BackColor = $C.DangerHov })
$UnblockAllBtn.Add_MouseLeave({ $UnblockAllBtn.BackColor = $C.Danger })

# Refresh button
$RefreshBtn = New-Object System.Windows.Forms.Button
$RefreshBtn.Location  = New-Object System.Drawing.Point(0, 448)
$RefreshBtn.Size      = New-Object System.Drawing.Size(242, 28)
$RefreshBtn.Text      = "-  Refresh List"
$RefreshBtn.FlatStyle = "Flat"
$RefreshBtn.FlatAppearance.BorderSize  = 1
$RefreshBtn.FlatAppearance.BorderColor = $C.Border
$RefreshBtn.BackColor = $C.BG
$RefreshBtn.ForeColor = $C.Muted
$RefreshBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$RefreshBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$RightPanel.Controls.Add($RefreshBtn)

# -- STATUS BAR ------------------------------
$StatusBar = New-Object System.Windows.Forms.Panel
$StatusBar.Location  = New-Object System.Drawing.Point(0, 582)
$StatusBar.Size      = New-Object System.Drawing.Size(700, 30)
$StatusBar.BackColor = $C.Surface
$Form.Controls.Add($StatusBar)

$StatusDot = New-Object System.Windows.Forms.Label
$StatusDot.Location  = New-Object System.Drawing.Point(14, 7)
$StatusDot.Size      = New-Object System.Drawing.Size(12, 12)
$StatusDot.BackColor = $C.Success
$StatusBar.Controls.Add($StatusDot)

$StatusLbl = New-Object System.Windows.Forms.Label
$StatusLbl.Location  = New-Object System.Drawing.Point(32, 5)
$StatusLbl.Size      = New-Object System.Drawing.Size(500, 20)
$StatusLbl.Text      = "Ready - hosts-file method is instant and requires no restart"
$StatusLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$StatusLbl.ForeColor = $C.Muted
$StatusBar.Controls.Add($StatusLbl)

$MethodLbl = New-Object System.Windows.Forms.Label
$MethodLbl.Location  = New-Object System.Drawing.Point(535, 5)
$MethodLbl.Size      = New-Object System.Drawing.Size(155, 20)
$MethodLbl.Text      = "Method: HOSTS + DNS flush"
$MethodLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$MethodLbl.ForeColor = $C.Muted
$MethodLbl.TextAlign = "MiddleRight"
$StatusBar.Controls.Add($MethodLbl)

function Set-Status($msg, $color = $null) {
    $StatusLbl.Text      = $msg
    $StatusDot.BackColor = if ($color) { $color } else { $C.Success }
}

# ---------------------------------------------
# BUTTON HANDLERS
# ---------------------------------------------

$BlockBtn.Add_Click({
    $raw = $DomainBox.Text -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
    if ($raw.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please enter at least one domain.", "No Input",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $BlockBtn.Enabled       = $false
    $UnblockAllBtn.Enabled  = $false
    Set-Status "Blocking $($raw.Count) domain(s)..." $C.Yellow
    $Form.Refresh()

    try {
        $count = Block-Domains -Domains $raw -UseFirewall $FwCheck.Checked -BlockWWW $WwwCheck.Checked
        Refresh-List
        Set-Status "Done - $count new rule(s) added" $C.Success
        $DomainBox.Clear()
    } catch {
        Set-Status "Error: $_" $C.Danger
    } finally {
        $BlockBtn.Enabled      = $true
        $UnblockAllBtn.Enabled = $true
    }
})

$UnblockAllBtn.Add_Click({
    $n = @(Get-BlockedDomains).Count
    if ($n -eq 0) { Set-Status "Nothing to unblock" $C.Muted; return }

    $r = [System.Windows.Forms.MessageBox]::Show(
        "Remove all $n blocked domain(s)?",
        "Confirm Unblock All",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)

    if ($r -ne "Yes") { return }

    $BlockBtn.Enabled      = $false
    $UnblockAllBtn.Enabled = $false
    Set-Status "Removing all blocks..." $C.Yellow
    $Form.Refresh()

    try {
        Unblock-AllDomains | Out-Null
        Refresh-List
        Set-Status "All blocks removed" $C.Success
    } catch {
        Set-Status "Error: $_" $C.Danger
    } finally {
        $BlockBtn.Enabled      = $true
        $UnblockAllBtn.Enabled = $true
    }
})

$RemoveSelBtn.Add_Click({
    $sel = $ActiveList.SelectedItems
    if ($sel.Count -eq 0) { return }

    $domains = @($sel | ForEach-Object { $_ })
    Set-Status "Removing $($domains.Count) domain(s)..." $C.Yellow
    $Form.Refresh()

    $removed = Unblock-SelectedDomains -Domains $domains
    Refresh-List
    Set-Status "Removed $removed domain(s)" $C.Success
})

$RefreshBtn.Add_Click({
    Refresh-List
    Set-Status "List refreshed - $(@(Get-BlockedDomains).Count) active block(s)"
})

# -- LAUNCH ----------------------------------
$Form.Add_Shown({
    Refresh-List
    $DomainBox.Focus()
})

[void]$Form.ShowDialog()
