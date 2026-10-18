###############################################################
# Parallels RAS Retro Gateway Service v1.29
# Parallels RAS Commodore 64 Gateway
# Based on stable v0.80 flow
# Protocol: RGP/0.95 RAW TCP 40x25 screen protocol
###############################################################

$Version = "1.29"
$Protocol = "RGP/1.24"
$Port = 6464

# Shared ASCII key: match KY$ in the BASIC source. Never sent over TCP.
$AuthenticationKey = "0123456789ABCDEF0123456789ABCDEF"
if ($AuthenticationKey -cnotmatch "^[0-9A-F]{32}$") { throw "Configure a 32-character uppercase hexadecimal authentication key." }
$script:NextAuthenticatedClient = $null

# RAS connection settings
$RasServer = "ras-gateway01.example.local"
$RasUsername = "c64operator@example.local"

# Display settings shown on the C64.
# Gateway DNS is the public endpoint the C64 dials.
# RAS/CB name, farm name, hosts and hostpools are resolved programmatically.
# If a value cannot be resolved, the screen shows UNKNOWN instead of a guessed value.
$GatewayDns = "ras-gateway.example.net"

# v1.01 render-speed pass: send C64 screen codes; C64 buffers off-screen then copies to screen RAM.
$SendChunkSize = 1000
$SendDelayMs = 0
$PostSendHoldSeconds = 0
$ProgressStep = 1000

$RasPassword = Read-Host "Password for $RasUsername" -AsSecureString

Import-Module RASAdmin -ErrorAction Stop

Write-Host ""
Write-Host "Connecting to Parallels RAS..." -ForegroundColor Cyan

try {
    New-RASSession `
        -Server $RasServer `
        -Username $RasUsername `
        -Password $RasPassword

    Write-Host "Connected successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: Unable to connect to RAS." -ForegroundColor Red
    Write-Host $_
    exit 1
}

function Get-RetroConnectionBrokerName {
    # Return the RAS Publishing Agent / Connection Broker the PS1 connects to.
    # When the RAS session uses localhost on the RAS server, resolve the actual
    # Windows computer name programmatically instead of displaying LOCALHOST.
    try {
        if (-not [string]::IsNullOrWhiteSpace($RasServer)) {
            $normalized = $RasServer.Trim().ToLowerInvariant()
            if ($normalized -ne "localhost" -and $normalized -ne "127.0.0.1" -and $normalized -ne "::1") {
                return $RasServer.Trim().ToUpperInvariant()
            }
        }

        $hostName = [System.Net.Dns]::GetHostName()
        if (-not [string]::IsNullOrWhiteSpace($hostName)) { return $hostName.ToUpperInvariant() }
        if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { return $env:COMPUTERNAME.ToUpperInvariant() }
    }
    catch { }

    return "UNKNOWN"
}

function Get-RetroFarmName {
    # v0.91: exact verified cmdlet expression after New-RASSession:
    # (Get-RASFarmSettings).Name
    try {
        $value = (Get-RASFarmSettings).Name
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return ([string]$value).Trim().ToUpperInvariant()
        }
    }
    catch {
        Write-Host "Farm name lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return "UNKNOWN"
}

function Get-CountFromCandidateCommands {
    param([string[]]$Commands)

    foreach ($cmd in $Commands) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            try {
                $items = & $cmd -ErrorAction Stop
                if ($null -ne $items) { return @($items).Count }
            }
            catch { }
        }
    }

    return "UNKNOWN"
}

function Get-RetroHostCount {
    $candidateCommands = @(
        "Get-RASRDSessionHost",
        "Get-RASRDSHost",
        "Get-RASRDSServer",
        "Get-RASRDSHosts",
        "Get-RASRDSServers",
        "Get-RDSHost",
        "Get-RDSHosts",
        "Get-RDSServer",
        "Get-RDSServers",
        "Get-RASAVDHost",
        "Get-RASAVDHosts",
        "Get-RASVDIHost",
        "Get-RASVDIHosts"
    )

    $count = Get-CountFromCandidateCommands -Commands $candidateCommands
    if ($count -ne "UNKNOWN") { return ([string]$count).Trim() }

    # Fallback for RDSH-only view: derive host count from the RDSIds stored on RDSH host pools.
    # This matches what Get-RASRDSHostPool shows in the RDSIds column and avoids hiding the value
    # when a host-list cmdlet name differs between RAS versions.
    try {
        $ids = @()
        $pools = Get-RASRDSHostPool -ErrorAction Stop
        foreach ($pool in @($pools)) {
            if ($null -ne $pool.RDSIds) { $ids += @($pool.RDSIds) }
        }
        if ($ids.Count -gt 0) { return ([string](@($ids | Select-Object -Unique).Count)).Trim() }
        return "0"
    }
    catch {
        Write-Host "RDSH host count fallback failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return "UNKNOWN"
}

function Get-RetroHostPoolCount {
    # v0.91: exact verified cmdlet expression after New-RASSession:
    # (Get-RASRDSHostPool | Measure-Object).Count
    try {
        $count = (Get-RASRDSHostPool | Measure-Object).Count
        if ($null -ne $count) { return ([string]$count).Trim() }
    }
    catch {
        Write-Host "RDSH host pool count lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return "UNKNOWN"
}

function Get-RetroAvdHostPoolCount {
    # v1.05: AVD host pool count, same pattern as RDSH pools.
    # Verified intended expression:
    # (Get-RASAVDHostPool | Measure-Object).Count
    try {
        $count = (Get-RASAVDHostPool | Measure-Object).Count
        if ($null -ne $count) { return ([string]$count).Trim() }
    }
    catch {
        Write-Host "AVD host pool count lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return "UNKNOWN"
}

function Get-RetroVdiHostPoolCount {
    # v1.06: VDI host pool count.
    # Requested cmdlet:
    # (Get-RASVDIHostPool | Measure-Object).Count
    # If the cmdlet returns nothing, show 0.
    try {
        $items = Get-RASVDIHostPool -ErrorAction Stop
        if ($null -eq $items) { return "0" }
        $count = @($items).Count
        return ([string]$count).Trim()
    }
    catch {
        Write-Host "VDI host pool count lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return "UNKNOWN"
}

function Convert-ToRetroSafe {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    $upper = $Text.ToUpperInvariant()
    $sb = [System.Text.StringBuilder]::new()

    foreach ($ch in $upper.ToCharArray()) {
        $n = [int][char]$ch
        if ($n -ge 32 -and $n -le 126) { [void]$sb.Append($ch) }
        else { [void]$sb.Append("?") }
    }

    return $sb.ToString()
}

function New-Screen {
    $script:ScreenLines = @()
    for ($i = 0; $i -lt 25; $i++) { $script:ScreenLines += (" " * 40) }
}

function Put-Text {
    param(
        [int]$Row,
        [int]$Col,
        [string]$Text
    )

    if ($Row -lt 0 -or $Row -gt 24) { return }
    if ($Col -lt 0 -or $Col -gt 39) { return }

    $safe = Convert-ToRetroSafe $Text
    $max = 40 - $Col
    if ($safe.Length -gt $max) { $safe = $safe.Substring(0, $max) }

    $line = $script:ScreenLines[$Row]
    $before = if ($Col -gt 0) { $line.Substring(0, $Col) } else { "" }
    $afterStart = $Col + $safe.Length
    $after = if ($afterStart -lt 40) { $line.Substring($afterStart) } else { "" }
    $script:ScreenLines[$Row] = ($before + $safe + $after).PadRight(40).Substring(0,40)
}

function Put-Centered {
    param(
        [int]$Row,
        [string]$Text
    )

    $safe = Convert-ToRetroSafe $Text
    if ($safe.Length -gt 38) { $safe = $safe.Substring(0,38) }
    $padLeft = [Math]::Floor((38 - $safe.Length) / 2)
    $line = "*" + (" " * $padLeft) + $safe
    $line = $line.PadRight(39, " ") + "*"
    Put-Text -Row $Row -Col 0 -Text $line
}

function Box-Line {
    param([int]$Row)
    Put-Text -Row $Row -Col 0 -Text ("*" * 40)
}

function Render-Screen {
    $screen = [string]::Concat($script:ScreenLines)
    if ($screen.Length -lt 1000) { $screen = $screen.PadRight(1000, " ") }
    if ($screen.Length -gt 1000) { $screen = $screen.Substring(0,1000) }
    return $screen
}

function New-MainScreen {
    $time = Get-Date -Format "HH:mm:ss"
    $displayRasServer = Get-RetroConnectionBrokerName
    $farmName = Get-RetroFarmName
    $hostCount = Get-RetroHostCount
    $hostPoolCount = Get-RetroHostPoolCount
    $vdiHostPoolCount = Get-RetroVdiHostPoolCount
    $avdHostPoolCount = Get-RetroAvdHostPoolCount

    New-Screen

    Box-Line 0
    Put-Centered 1 "PARALLELS RAS C64 ADMIN CONSOLE"
    Box-Line 2

    Put-Text 6 0 "FARM      : $farmName"
    Put-Text 7 0 "GATEWAY   : $GatewayDns"
    Put-Text 8 0 "STATUS    : CONNECTED"
    Put-Text 9 0 "PROTOCOL  : $Protocol"
    Put-Text 10 0 "TIME      : $time"

    $hostPoolText = ([string]$hostPoolCount).Trim()
    if ([string]::IsNullOrWhiteSpace($hostPoolText)) { $hostPoolText = "UNKNOWN" }
    $vdiHostPoolText = ([string]$vdiHostPoolCount).Trim()
    if ([string]::IsNullOrWhiteSpace($vdiHostPoolText)) { $vdiHostPoolText = "UNKNOWN" }
    $avdHostPoolText = ([string]$avdHostPoolCount).Trim()
    if ([string]::IsNullOrWhiteSpace($avdHostPoolText)) { $avdHostPoolText = "UNKNOWN" }
    $hostText = ([string]$hostCount).Trim()
    if ([string]::IsNullOrWhiteSpace($hostText)) { $hostText = "UNKNOWN" }

    # Keep labels short so counts remain visible on a 40-column screen.
    Put-Text 11 0 ("RDSH POOLS : " + $hostPoolText)
    Put-Text 12 0 ("VDI POOLS  : " + $vdiHostPoolText)
    Put-Text 13 0 ("AVD POOLS  : " + $avdHostPoolText)
    Put-Text 14 0 ("HOSTS      : " + $hostText)

    Put-Text 16 0 "MENU"
    Put-Text 18 0 "F1 FARMS F2 SITES  F3 POOLS  F4 HOSTS"
    Put-Text 19 0 "F5 SESS  F6 APPS             F8 QUIT"

    return Render-Screen
}

function New-HelpScreen {
    New-Screen
    Box-Line 0
    Put-Centered 1 "RETRO GATEWAY HELP"
    Box-Line 2
    Put-Text 4 0 "COMMANDS"
    Put-Text 6 0 "S  MAIN SCREEN"
    Put-Text 7 0 "F  FARMS"
    Put-Text 8 0 "P  PING"
    Put-Text 9 0 "H  HELP"
    Put-Text 11 0 "RGP SENDS 40X25 SCREEN BUFFERS."
    Put-Text 13 0 "THE C64 ONLY RENDERS THE SCREEN."
    Put-Text 23 0 "READY."
    return Render-Screen
}

function New-FarmScreen {
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS FARMS"
    Box-Line 2

    # The C64 has 40 columns: 24 for the name, one gap, 15 for this heading.
    Put-Text 4 0 "NAME                     NUMBER OF SITES"
    Put-Text 5 0 "------------------------ ---------------"
    try {
        $farmName = ([string](Get-RASFarmSettings -ErrorAction Stop).Name).Trim().ToUpperInvariant()
        $sites = @(Get-RASSite -ErrorAction Stop)
        if ([string]::IsNullOrWhiteSpace($farmName)) {
            Put-Text 7 0 "NO FARM NAME RETURNED."
        }
        else {
            if ($farmName.Length -gt 24) { $farmName = $farmName.Substring(0,24) }
            Put-Text 6 0 $farmName.PadRight(24)
            Put-Text 6 25 ([string]$sites.Count)
        }
    }
    catch {
        Write-Host "Farm lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Put-Text 7 0 "ERROR RETRIEVING FARM."
    }
    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK                       F8 QUIT"
    return Render-Screen
}


function New-SitesScreen {
    # v1.11: Retrieve all Parallels RAS sites using Get-RASSite.
    # The C64 screen can display up to 15 sites at once.
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS SITES"
    Box-Line 2

    Put-Text 4 0 "ID   NAME                         LIC"
    Put-Text 5 0 "---- ---------------------------- ---"

    try {
        $sites = @(Get-RASSite -ErrorAction Stop)
        if ($sites.Count -eq 0) {
            Put-Text 7 0 "NO SITES RETURNED."
        }
        else {
            $row = 6
            foreach ($site in ($sites | Select-Object -First 15)) {
                $id = ([string]$site.Id).Trim()
                $name = ([string]$site.Name).Trim()
                $licensing = if ([bool]$site.LicensingSite) { "YES" } else { "NO" }

                if ($id.Length -gt 4) { $id = $id.Substring(0,4) }
                if ($name.Length -gt 28) { $name = $name.Substring(0,28) }

                Put-Text $row 0 $id.PadRight(4)
                Put-Text $row 5 $name.PadRight(28)
                Put-Text $row 34 $licensing
                $row++
            }

            if ($sites.Count -gt 15) {
                Put-Text 21 0 ("SHOWING 15 OF " + $sites.Count + " SITES")
            }
        }
    }
    catch {
        Write-Host "Site lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Put-Text 7 0 "ERROR RETRIEVING SITES."
    }

    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK                       F8 QUIT"
    return Render-Screen
}


function New-HostPoolsScreen {
    # v1.13: Combine RDSH, VDI and AVD host pools in one overview.
    # The C64 screen can display up to 15 pools at once.
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS HOST POOLS"
    Box-Line 2

    Put-Text 4 0 "TYPE SITEID ID   NAME"
    Put-Text 5 0 "---- ------ ---- -----------------------"

    $pools = @()
    $lookupErrors = @()

    try {
        foreach ($pool in @(Get-RASRDSHostPool -ErrorAction Stop)) {
            $pools += [PSCustomObject]@{
                SortOrder = 1
                PoolType = "RDSH"
                SiteId = $pool.SiteId
                Id = $pool.Id
                Name = $pool.Name
            }
        }
    }
    catch {
        $lookupErrors += "RDSH"
        Write-Host "RDSH host pool lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        # Important: the supported cmdlet name is singular.
        foreach ($pool in @(Get-RASVDIHostPool -ErrorAction Stop)) {
            $pools += [PSCustomObject]@{
                SortOrder = 2
                PoolType = "VDI"
                SiteId = $pool.SiteId
                Id = $pool.Id
                Name = $pool.Name
            }
        }
    }
    catch {
        $lookupErrors += "VDI"
        Write-Host "VDI host pool lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        foreach ($pool in @(Get-RASAVDHostPool -ErrorAction Stop)) {
            $pools += [PSCustomObject]@{
                SortOrder = 3
                PoolType = "AVD"
                SiteId = $pool.SiteId
                Id = $pool.Id
                Name = $pool.Name
            }
        }
    }
    catch {
        $lookupErrors += "AVD"
        Write-Host "AVD host pool lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $pools = @($pools | Sort-Object SortOrder, SiteId, Name)

    if ($pools.Count -eq 0) {
        if ($lookupErrors.Count -gt 0) {
            Put-Text 7 0 "ERROR RETRIEVING HOST POOLS."
        }
        else {
            Put-Text 7 0 "NO HOST POOLS RETURNED."
        }
    }
    else {
        $row = 6
        foreach ($pool in ($pools | Select-Object -First 15)) {
            $type = ([string]$pool.PoolType).Trim()
            $siteId = ([string]$pool.SiteId).Trim()
            $id = ([string]$pool.Id).Trim()
            $name = ([string]$pool.Name).Trim()

            if ([string]::IsNullOrWhiteSpace($siteId)) { $siteId = "N/A" }
            if ([string]::IsNullOrWhiteSpace($id)) { $id = "N/A" }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "N/A" }

            if ($type.Length -gt 4) { $type = $type.Substring(0,4) }
            if ($siteId.Length -gt 6) { $siteId = $siteId.Substring(0,6) }
            if ($id.Length -gt 4) { $id = $id.Substring(0,4) }
            if ($name.Length -gt 23) { $name = $name.Substring(0,23) }

            Put-Text $row 0 $type.PadRight(4)
            Put-Text $row 5 $siteId.PadLeft(6)
            Put-Text $row 12 $id.PadLeft(4)
            Put-Text $row 17 $name
            $row++
        }
    }

    Put-Text 21 0 ("SHOWING " + [Math]::Min(15, $pools.Count) + " OF " + $pools.Count + " POOLS")
    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK                       F8 QUIT"
    return Render-Screen
}


function New-HostsScreen {
    # v1.14: Combine RDSH, VDI and AVD hosts in one overview.
    # Host name property mapping:
    # RDSH = Server, VDI = Name, AVD = Host.
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS HOSTS"
    Box-Line 2

    Put-Text 4 0 "TYPE SITE NAME"
    Put-Text 5 0 "---- ---- ------------------------------"

    $hosts = @()
    $lookupErrors = @()

    try {
        foreach ($hostItem in @(Get-RASRDSHost -ErrorAction Stop)) {
            $hosts += [PSCustomObject]@{
                SortOrder = 1
                HostType = "RDSH"
                SiteId = $hostItem.SiteId
                Name = $hostItem.Server
            }
        }
    }
    catch {
        $lookupErrors += "RDSH"
        Write-Host "RDSH host lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        foreach ($hostItem in @(Get-RASVDIHost -ErrorAction Stop)) {
            $hosts += [PSCustomObject]@{
                SortOrder = 2
                HostType = "VDI"
                SiteId = $hostItem.SiteId
                Name = $hostItem.Name
            }
        }
    }
    catch {
        $lookupErrors += "VDI"
        Write-Host "VDI host lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        foreach ($hostItem in @(Get-RASAVDHost -ErrorAction Stop)) {
            $hosts += [PSCustomObject]@{
                SortOrder = 3
                HostType = "AVD"
                SiteId = $hostItem.SiteId
                Name = $hostItem.Host
            }
        }
    }
    catch {
        $lookupErrors += "AVD"
        Write-Host "AVD host lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $hosts = @($hosts | Sort-Object SortOrder, SiteId, Name)

    if ($hosts.Count -eq 0) {
        if ($lookupErrors.Count -gt 0) {
            Put-Text 7 0 "ERROR RETRIEVING HOSTS."
        }
        else {
            Put-Text 7 0 "NO HOSTS RETURNED."
        }
    }
    else {
        $row = 6
        foreach ($hostItem in ($hosts | Select-Object -First 15)) {
            $type = ([string]$hostItem.HostType).Trim()
            $siteId = ([string]$hostItem.SiteId).Trim()
            $name = ([string]$hostItem.Name).Trim()

            if ([string]::IsNullOrWhiteSpace($siteId)) { $siteId = "N/A" }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "N/A" }

            if ($type.Length -gt 4) { $type = $type.Substring(0,4) }
            if ($siteId.Length -gt 4) { $siteId = $siteId.Substring(0,4) }
            if ($name.Length -gt 30) { $name = $name.Substring(0,30) }

            Put-Text $row 0 $type.PadRight(4)
            Put-Text $row 5 $siteId.PadLeft(4)
            Put-Text $row 10 $name
            $row++
        }
    }

    Put-Text 21 0 ("SHOWING " + [Math]::Min(15, $hosts.Count) + " OF " + $hosts.Count + " HOSTS")
    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK                       F8 QUIT"
    return Render-Screen
}


function New-SessionsScreen {
    # v1.15: Display connected sessions from all supported host types.
    # Source mapping: RDS = RDSH, VDI = VDI, AVD = AVD.
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS SESSIONS"
    Box-Line 2

    Put-Text 4 0 "TYPE USER            HOST         STATE"
    Put-Text 5 0 "---- --------------- ------------ -------"

    $sessions = @()

    try {
        $sessions = @(Get-RASRDSession -ErrorAction Stop | ForEach-Object {
            $source = ([string]$_.Source).Trim().ToUpperInvariant()
            $sessionType = switch ($source) {
                "RDS"  { "RDSH" }
                "RDSH" { "RDSH" }
                "VDI"  { "VDI" }
                "AVD"  { "AVD" }
                default {
                    if ([string]::IsNullOrWhiteSpace($source)) { "N/A" }
                    elseif ($source.Length -gt 4) { $source.Substring(0,4) }
                    else { $source }
                }
            }

            [PSCustomObject]@{
                SessionType = $sessionType
                User = $_.User
                Host = $_.SessionHostName
                State = $_.State
            }
        })

        $typeOrder = @{ "RDSH" = 1; "VDI" = 2; "AVD" = 3 }
        $sessions = @($sessions | Sort-Object `
            @{ Expression = {
                if ($typeOrder.ContainsKey($_.SessionType)) {
                    $typeOrder[$_.SessionType]
                }
                else {
                    9
                }
            } }, User, Host)
    }
    catch {
        Write-Host "Session lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Put-Text 7 0 "ERROR RETRIEVING SESSIONS."
    }

    if ($sessions.Count -eq 0) {
        Put-Text 7 0 "NO CONNECTED SESSIONS."
    }
    else {
        $row = 6
        foreach ($session in ($sessions | Select-Object -First 15)) {
            $type = ([string]$session.SessionType).Trim()
            $user = ([string]$session.User).Trim()
            $hostName = ([string]$session.Host).Trim()
            $state = ([string]$session.State).Trim()

            # Display only the username portion before the @ character.
            if ($user.Contains("@")) {
                $user = $user.Split("@", 2)[0]
            }

            if ([string]::IsNullOrWhiteSpace($type)) { $type = "N/A" }
            if ([string]::IsNullOrWhiteSpace($user)) { $user = "N/A" }
            if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = "N/A" }
            if ([string]::IsNullOrWhiteSpace($state)) { $state = "N/A" }

            if ($type.Length -gt 4) { $type = $type.Substring(0,4) }
            if ($user.Length -gt 15) { $user = $user.Substring(0,15) }
            if ($hostName.Length -gt 12) { $hostName = $hostName.Substring(0,12) }
            if ($state.Length -gt 7) { $state = $state.Substring(0,7) }

            Put-Text $row 0 $type.PadRight(4)
            Put-Text $row 5 $user.PadRight(15)
            Put-Text $row 21 $hostName.PadRight(12)
            Put-Text $row 34 $state
            $row++
        }
    }

    Put-Text 21 0 ("SHOWING " + [Math]::Min(15, $sessions.Count) + " OF " + $sessions.Count + " SESSIONS")
    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK  F2 MESSAGE           F8 QUIT"
    return Render-Screen
}

function New-MessageResultScreen {
    param([string]$Message)

    New-Screen
    Box-Line 0
    Put-Centered 1 "RAS SESSION MESSAGE"
    Box-Line 2

    $messageText = ([string]$Message).Trim()
    if ($messageText.Length -gt 38) {
        $messageText = $messageText.Substring(0,38)
    }

    if ([string]::IsNullOrWhiteSpace($messageText)) {
        Put-Text 6 0 "MESSAGE NOT SENT."
        Put-Text 8 0 "THE MESSAGE WAS EMPTY."
        Put-Text 22 0 "MENU"
        Put-Text 23 0 "F1 BACK  F2 MESSAGE           F8 QUIT"
        return Render-Screen
    }

    $sent = 0
    $failed = 0
    $firstError = ""
    $rdsSessions = @()

    try {
        $rdsSessions = @(Get-RASRDSession -ErrorAction Stop | Where-Object {
            $source = ([string]$_.Source).Trim().ToUpperInvariant()
            $source -eq "RDS" -or $source -eq "RDSH"
        })

        foreach ($session in $rdsSessions) {
            $rdsId = $session.SessionHostId
            if ($null -eq $rdsId -or [uint32]$rdsId -eq 0) {
                $rdsId = $session.ServerID
            }

            $server = ([string]$session.SessionHostName).Trim()
            $sessionId = $session.SessionID

            if (($null -eq $rdsId -or [uint32]$rdsId -eq 0) -or $null -eq $sessionId) {
                $failed++
                if ([string]::IsNullOrWhiteSpace($firstError)) {
                    $firstError = "MISSING HOST OR SESSION ID"
                }
                continue
            }

            try {
                # Target the RDSH server by its farm ID. This avoids
                # exact-name matching issues with FQDNs and aliases.
                Invoke-RASRDSHostSessionCmd `
                    -RDSId ([uint32]$rdsId) `
                    -Command SendMsg `
                    -Id ([uint32]$sessionId) `
                    -MsgTitle "RAS MESSAGE" `
                    -Message $messageText `
                    -ErrorAction Stop
                $sent++
            }
            catch {
                $failed++
                $errorText = $_.Exception.Message
                if ([string]::IsNullOrWhiteSpace($firstError)) {
                    $firstError = $errorText
                }
                Write-Host "Message failed for RDS host ID $rdsId ($server), session $sessionId`: $errorText" -ForegroundColor DarkYellow
            }
        }

        if ($rdsSessions.Count -eq 0) {
            Put-Text 6 0 "NO RDSH SESSIONS FOUND."
        }
        elseif ($failed -eq 0) {
            Put-Text 6 0 "MESSAGE SENT SUCCESSFULLY."
        }
        else {
            Put-Text 6 0 "MESSAGE PROCESSING COMPLETE."
        }
    }
    catch {
        Put-Text 6 0 "ERROR RETRIEVING RDSH SESSIONS."
        Write-Host "RDSH session lookup failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Put-Text 9 0 ("SENT   : " + $sent)
    Put-Text 10 0 ("FAILED : " + $failed)

    if ($failed -gt 0 -and -not [string]::IsNullOrWhiteSpace($firstError)) {
        $displayError = $firstError.ToUpperInvariant()
        if ($displayError.Length -gt 38) {
            $displayError = $displayError.Substring(0,38)
        }
        Put-Text 12 0 "FIRST ERROR:"
        Put-Text 13 0 $displayError
        Put-Text 15 0 "MESSAGE:"
        Put-Text 16 0 $messageText
    }
    else {
        Put-Text 12 0 "MESSAGE:"
        Put-Text 13 0 $messageText
    }
    Put-Text 22 0 "MENU"
    Put-Text 23 0 "F1 BACK  F2 MESSAGE           F8 QUIT"
    return Render-Screen
}


function New-ApplicationsScreen {
    param([int]$Page = 1)

    # v1.22: Combined published applications with paging.
    # Long Target paths are left-truncated so the executable name remains visible.
    New-Screen
    Box-Line 0
    Put-Centered 1 "PARALLELS RAS APPLICATIONS"
    Box-Line 2

    Put-Text 4 0 "TYPE NAME               PATH"
    Put-Text 5 0 "---- ------------------ ----------------"

    $apps = @()
    $lookupErrors = @()

    try {
        foreach ($app in @(Get-RASPubRDSApp -ErrorAction Stop)) {
            $apps += [PSCustomObject]@{
                SortOrder = 1
                AppType = "RDSH"
                Name = $app.Name
                Target = $app.Target
            }
        }
    }
    catch {
        $lookupErrors += "RDSH"
        Write-Host "RDSH published application lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        foreach ($app in @(Get-RASPubVDIApp -ErrorAction Stop)) {
            $apps += [PSCustomObject]@{
                SortOrder = 2
                AppType = "VDI"
                Name = $app.Name
                Target = $app.Target
            }
        }
    }
    catch {
        $lookupErrors += "VDI"
        Write-Host "VDI published application lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        foreach ($app in @(Get-RASPubAVDApp -ErrorAction Stop)) {
            $apps += [PSCustomObject]@{
                SortOrder = 3
                AppType = "AVD"
                Name = $app.Name
                Target = $app.Target
            }
        }
    }
    catch {
        $lookupErrors += "AVD"
        Write-Host "AVD published application lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $apps = @($apps | Sort-Object SortOrder, Name)

    $pageSize = 15
    $total = $apps.Count
    $totalPages = [Math]::Max(1, [Math]::Ceiling($total / [double]$pageSize))

    if ($Page -lt 1) { $Page = 1 }
    if ($Page -gt $totalPages) { $Page = $totalPages }

    $startIndex = ($Page - 1) * $pageSize
    $pageApps = @($apps | Select-Object -Skip $startIndex -First $pageSize)

    if ($apps.Count -eq 0) {
        if ($lookupErrors.Count -gt 0) {
            Put-Text 7 0 "ERROR RETRIEVING APPLICATIONS."
        }
        else {
            Put-Text 7 0 "NO PUBLISHED APPLICATIONS."
        }
    }
    else {
        $row = 6
        foreach ($app in $pageApps) {
            $type = ([string]$app.AppType).Trim()
            $name = ([string]$app.Name).Trim()
            $target = ([string]$app.Target).Trim()

            if ([string]::IsNullOrWhiteSpace($type)) { $type = "N/A" }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "N/A" }
            if ([string]::IsNullOrWhiteSpace($target)) { $target = "N/A" }

            if ($type.Length -gt 4) { $type = $type.Substring(0,4) }
            if ($name.Length -gt 18) { $name = $name.Substring(0,18) }

            if ($target.Length -gt 16) {
                $target = ".." + $target.Substring($target.Length - 14)
            }

            Put-Text $row 0 $type.PadRight(4)
            Put-Text $row 5 $name.PadRight(18)
            Put-Text $row 24 $target
            $row++
        }
    }

    if ($total -gt 0) {
        $firstShown = $startIndex + 1
        $lastShown = [Math]::Min($startIndex + $pageSize, $total)
        Put-Text 21 0 ("SHOWING " + $firstShown + "-" + $lastShown + " OF " + $total + " APPS")
    }
    else {
        Put-Text 21 0 "SHOWING 0 OF 0 APPS"
    }

    Put-Text 22 0 "MENU"

    $hasPrevious = $Page -gt 1
    $hasNext = $Page -lt $totalPages

    if ($hasPrevious -and $hasNext) {
        Put-Text 23 0 "F1 BACK F2 NEXT F3 PREV       F8 QUIT"
    }
    elseif ($hasNext) {
        Put-Text 23 0 "F1 BACK F2 NEXT               F8 QUIT"
    }
    elseif ($hasPrevious) {
        Put-Text 23 0 "F1 BACK         F3 PREV       F8 QUIT"
    }
    else {
        Put-Text 23 0 "F1 BACK                       F8 QUIT"
    }

    return Render-Screen
}

function New-PingScreen {
    New-Screen
    Box-Line 0
    Put-Centered 1 "PONG"
    Box-Line 2
    Put-Text 6 0 "RETRO GATEWAY IS ONLINE."
    Put-Text 8 0 "FARM      : $(Get-RetroFarmName)"
    Put-Text 23 0 "READY."
    return Render-Screen
}

function New-UnknownScreen {
    param([string]$Command)
    New-Screen
    Box-Line 0
    Put-Centered 1 "UNKNOWN COMMAND"
    Box-Line 2
    Put-Text 5 0 "COMMAND   : $Command"
    Put-Text 7 0 "USE S F P OR H"
    Put-Text 23 0 "READY."
    return Render-Screen
}

function New-Payload {
    param(
        [string]$Command,
        [string]$Argument
    )

    switch ($Command) {
        "S" { return @{ Name="SCREEN"; Text=(New-MainScreen) } }
        "F" { return @{ Name="FARM"; Text=(New-FarmScreen) } }
        "2" { return @{ Name="SITES"; Text=(New-SitesScreen) } }
        "3" { return @{ Name="POOLS"; Text=(New-HostPoolsScreen) } }
        "4" { return @{ Name="HOSTS"; Text=(New-HostsScreen) } }
        "5" { return @{ Name="SESSIONS"; Text=(New-SessionsScreen) } }
        "6" {
            $page = 1
            if (-not [string]::IsNullOrWhiteSpace($Argument)) {
                $parsedPage = 0
                if ([int]::TryParse($Argument, [ref]$parsedPage)) {
                    $page = $parsedPage
                }
            }
            return @{ Name="APPLICATIONS"; Text=(New-ApplicationsScreen -Page $page) }
        }
        "M" { return @{ Name="MESSAGE"; Text=(New-MessageResultScreen -Message $Argument) } }
        "P" { return @{ Name="PING"; Text=(New-PingScreen) } }
        "H" { return @{ Name="HELP"; Text=(New-HelpScreen) } }
        default { return @{ Name="UNKNOWN"; Text=(New-UnknownScreen -Command $Command) } }
    }
}

# Authentication has its own bounded reader. Never pass handshake data to RAW logs.
function Read-RgpAuthLine {
    param([System.Net.Sockets.TcpClient]$Client, [int]$TimeoutSeconds = 30)
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 1000
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $line = New-Object System.Text.StringBuilder
    $received = 0
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (-not $Client.Client.Poll(100000, [System.Net.Sockets.SelectMode]::SelectRead)) { continue }
        $value = $stream.ReadByte()
        if ($value -lt 0) { throw "Authentication connection closed." }
        $received++
        if ($received -gt 128) { throw "Authentication input too long." }
        if ($value -eq 13 -or $value -eq 10) {
            if ($line.Length -gt 0) { return $line.ToString() }
            continue
        }
        if ($value -lt 32 -or $value -gt 126) { throw "Invalid authentication input." }
        [void]$line.Append([char]$value)
    }
    throw "Authentication timed out."
}

function Write-RgpAuthLine {
    param([System.Net.Sockets.TcpClient]$Client, [string]$Line)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Line + "`r")
    $Client.GetStream().Write($bytes, 0, $bytes.Length)
}

function Confirm-RgpAuthentication {
    param([System.Net.Sockets.TcpClient]$Client)
    try {
        $hello = Read-RgpAuthLine -Client $Client -TimeoutSeconds 10
        if ($hello -cne "HELLO 1") { throw "Authentication required." }
        $nonceBytes = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($nonceBytes) } finally { $rng.Dispose() }
        $nonce = [System.BitConverter]::ToString($nonceBytes).Replace("-", "")
        Write-RgpAuthLine -Client $Client -Line ("CHALLENGE " + $nonce)
        $answer = Read-RgpAuthLine -Client $Client -TimeoutSeconds 30
        if ($answer -cnotmatch "^AUTH [0-9A-F]{64}$") { throw "Authentication failed." }
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        try {
            $hmac.Key = [System.Text.Encoding]::ASCII.GetBytes($AuthenticationKey)
            $expected = $hmac.ComputeHash([System.Text.Encoding]::ASCII.GetBytes("RAS64-AUTH/1:" + $nonce))
        }
        finally { $hmac.Dispose() }
        # Compare all 32 bytes; do not stop at the first mismatch.
        $difference = 0
        for ($i = 0; $i -lt 32; $i++) {
            $actual = [System.Convert]::ToByte($answer.Substring(5 + 2 * $i, 2), 16)
            $difference = $difference -bor ($expected[$i] -bxor $actual)
        }
        if ($difference -ne 0) { throw "Authentication failed." }
        Write-RgpAuthLine -Client $Client -Line "OK"
        Write-Host "$(Get-Date -Format 'HH:mm:ss') AUTHENTICATED" -ForegroundColor Green
        return $true
    }
    catch {
        # Do not log exception contents, challenge, response, or secret key.
        Write-Host "$(Get-Date -Format 'HH:mm:ss') AUTH REJECTED / TIMEOUT" -ForegroundColor Yellow
        try { Write-RgpAuthLine -Client $Client -Line "DENIED" } catch { }
        return $false
    }
}

function Read-RgpCommand {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [System.Net.Sockets.TcpClient]$Client,
        [System.Net.Sockets.TcpListener]$Listener
    )

    # Wake periodically without treating an idle client as disconnected.
    # Keep partial command bytes until a terminator arrives.
    $Stream.ReadTimeout = 30000
    $bytes = New-Object System.Collections.Generic.List[byte]

    $lastIdleLog = Get-Date
    while ($bytes.Count -lt 128) {
        # Dedicated single-console gateway: a new caller replaces the old client.
        # Poll once per second so an idle/stale read cannot block replacement.
        if ($Listener.Pending()) {
            $candidate = $Listener.AcceptTcpClient()
            $candidate.NoDelay = $true
            $candidate.SendTimeout = 5000
            $candidateStream = $candidate.GetStream()
            $accepted = $false
            try { $accepted = Confirm-RgpAuthentication -Client $candidate }
            catch { Write-Host "Replacement authentication failed." -ForegroundColor Yellow }
            if ($accepted) {
                $script:NextAuthenticatedClient = $candidate
                Write-Host "AUTHENTICATED REPLACEMENT - releasing old client" -ForegroundColor Yellow
                return @{ Raw = ""; Command = ""; Argument = "" }
            }
            $candidateStream.Close()
            $candidate.Close()
        }
        if (-not $Client.Client.Poll(1000000, [System.Net.Sockets.SelectMode]::SelectRead)) {
            if (((Get-Date) - $lastIdleLog).TotalSeconds -ge 30) {
                $time = Get-Date -Format "HH:mm:ss"
                Write-Host "$time IDLE - no disconnect detected ($($bytes.Count) buffered bytes)" -ForegroundColor DarkGray
                $lastIdleLog = Get-Date
            }
            continue
        }
        try {
            $value = $Stream.ReadByte()
        }
        catch {
            # PowerShell can wrap the IOException in a method-invocation exception.
            $socketError = $_.Exception
            while ($null -ne $socketError -and
                   -not ($socketError -is [System.Net.Sockets.SocketException])) {
                $socketError = $socketError.InnerException
            }
            if ($null -eq $socketError -or
                $socketError.SocketErrorCode -ne [System.Net.Sockets.SocketError]::TimedOut) {
                throw
            }

            # Poll detects a reported close/error, not a silently dropped TCP path.
            $time = Get-Date -Format "HH:mm:ss"
            $socket = $Client.Client
            if (-not $Client.Connected -or
                $socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectError) -or
                ($socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and
                 $socket.Available -eq 0)) {
                Write-Host "$time CONNECTION LOST" -ForegroundColor Yellow
                return @{ Raw = ""; Command = ""; Argument = "" }
            }
            Write-Host "$time IDLE - no disconnect detected ($($bytes.Count) buffered bytes)" -ForegroundColor DarkGray
            continue
        }
        if ($value -lt 0) {
            $time = Get-Date -Format "HH:mm:ss"
            Write-Host "$time CONNECTION CLOSED BY PEER" -ForegroundColor Yellow
            return @{ Raw = ""; Command = ""; Argument = "" }
        }
        if ($value -eq 13 -or $value -eq 10) { break }
        $bytes.Add([byte]$value)
    }

    $raw = ""
    if ($bytes.Count -gt 0) {
        $raw = [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
    }

    $line = $raw.Trim()
    $command = ""
    $argument = ""

    if ($line.Length -gt 0) {
        $command = $line.Substring(0,1).ToUpperInvariant()
        if ($line.Length -gt 1) {
            $argument = $line.Substring(1).Trim()
        }
    }

    return @{
        Raw = $raw
        Command = $command
        Argument = $argument
    }
}

function Convert-ToC64ScreenBytes {
    param([string]$Text)

    $bytes = New-Object byte[] 1000
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -lt 1000) { $Text = $Text.PadRight(1000, " ") }
    if ($Text.Length -gt 1000) { $Text = $Text.Substring(0,1000) }

    for ($i = 0; $i -lt 1000; $i++) {
        $n = [int][char]$Text[$i]
        $screen = 32
        if ($n -ge 97 -and $n -le 122) { $screen = $n - 96 }
        elseif ($n -ge 65 -and $n -le 90) { $screen = $n - 64 }
        elseif ($n -eq 64) { $screen = 0 }
        elseif ($n -eq 95) { $screen = 100 }
        elseif ($n -ge 32 -and $n -lt 64) { $screen = $n }
        else { $screen = 32 }
        $bytes[$i] = [byte]$screen
    }

    return $bytes
}

function Convert-ToSparseRowBytes {
    param([byte[]]$ScreenBytes)

    # Binary format:
    #   byte 0: number of populated rows
    #   for each populated row:
    #     byte: row index (0-24)
    #     40 bytes: complete row in C64 screen codes
    $encoded = New-Object System.Collections.Generic.List[byte]
    $encoded.Add([byte]0)
    $rowCount = 0

    for ($row = 0; $row -lt 25; $row++) {
        $offset = $row * 40
        $hasContent = $false

        for ($column = 0; $column -lt 40; $column++) {
            if ($ScreenBytes[$offset + $column] -ne 32) {
                $hasContent = $true
                break
            }
        }

        if (-not $hasContent) {
            continue
        }

        $encoded.Add([byte]$row)
        for ($column = 0; $column -lt 40; $column++) {
            $encoded.Add($ScreenBytes[$offset + $column])
        }
        $rowCount++
    }

    $encoded[0] = [byte]$rowCount

    return @{
        Bytes = $encoded.ToArray()
        Rows = $rowCount
    }
}

function Write-RgpScreenBytes {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [byte[]]$Bytes,
        [string]$Time
    )

    $sent = 0
    try {
        while ($sent -lt $Bytes.Length) {
            $count = [Math]::Min($SendChunkSize, $Bytes.Length - $sent)
            $Stream.Write($Bytes, $sent, $count)
            $Stream.Flush()
            $sent += $count

            if (($sent % $ProgressStep) -eq 0 -or $sent -eq $Bytes.Length) {
                Write-Host "$time SENT $sent / $($Bytes.Length) BYTES" -ForegroundColor DarkGray
            }

            if ($SendDelayMs -gt 0) { Start-Sleep -Milliseconds $SendDelayMs }
        }
        return @{ Sent=$sent; Complete=$true; Error=$null }
    }
    catch {
        Write-Host "$time ERROR AFTER $sent BYTES: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Sent=$sent; Complete=$false; Error=$_.Exception.Message }
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Clear-Host
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "       Parallels RAS Retro Gateway Service v$Version"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " RAS Session : $RasServer"
Write-Host " Gateway DNS : $GatewayDns"
Write-Host " User        : $RasUsername"
Write-Host " Farm        : $(Get-RetroFarmName)"
Write-Host " RDSH Pools  : $(Get-RetroHostPoolCount)"
Write-Host " VDI Pools   : $(Get-RetroVdiHostPoolCount)"
Write-Host " AVD Pools   : $(Get-RetroAvdHostPoolCount)"
Write-Host " Hosts       : $(Get-RetroHostCount)"
Write-Host " Port        : $Port"
Write-Host " Protocol    : $Protocol"
Write-Host " Send Mode   : SPARSE C64 SCREEN ROWS"
Write-Host " Authentication : HMAC-SHA256 CHALLENGE / RESPONSE"
Write-Host " Connection  : PERSISTENT"
Write-Host " Hold Open   : DISABLED"
Write-Host ""
Write-Host " Commands    : S main; F farms; 2 sites; 3 pools; 4 hosts; 5 sessions; 6 page; M message; Q quit"
Write-Host ""
Write-Host " Waiting for Commodore 64..."
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

try {
    while ($true) {
        $alreadyAuthenticated = $false
        if ($null -ne $script:NextAuthenticatedClient) {
            $client = $script:NextAuthenticatedClient
            $script:NextAuthenticatedClient = $null
            $alreadyAuthenticated = $true
        }
        else { $client = $listener.AcceptTcpClient() }
        $client.NoDelay = $true
        $client.SendTimeout = 30000
        $client.ReceiveTimeout = 30000
        $stream = $client.GetStream()
        $connectTime = Get-Date -Format "HH:mm:ss"
        $remote = $client.Client.RemoteEndPoint.ToString().Split(":")[0]

        Write-Host "$connectTime CONNECT $remote - PERSISTENT" -ForegroundColor Cyan

        try {
            # Windows tcp_keepalive: enabled, idle time (ms), retry interval (ms).
            # TCP probes add no bytes to the C64 application protocol.
            $keepAlive = New-Object byte[] 12
            [System.BitConverter]::GetBytes([uint32]1).CopyTo($keepAlive, 0)
            [System.BitConverter]::GetBytes([uint32]30000).CopyTo($keepAlive, 4)
            [System.BitConverter]::GetBytes([uint32]5000).CopyTo($keepAlive, 8)
            try {
                [void]$client.Client.IOControl(
                    [System.Net.Sockets.IOControlCode]::KeepAliveValues,
                    $keepAlive,
                    $null
                )
                Write-Host "$connectTime TCP KEEPALIVE ENABLED - idle 30s / retry 5s" -ForegroundColor Cyan
            }
            catch {
                # Keep the existing gateway usable, but make a failed test setup clear.
                Write-Host "$connectTime WARNING - TCP keepalive setup failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }

            if (-not $alreadyAuthenticated) {
                if (-not (Confirm-RgpAuthentication -Client $client)) { continue }
            }
            while ($client.Connected) {
                $cmdInfo = Read-RgpCommand -Stream $stream -Client $client -Listener $listener

                # An empty read indicates that the C64/modem closed the connection.
                if ([string]::IsNullOrWhiteSpace($cmdInfo.Command)) {
                    break
                }

                $time = Get-Date -Format "HH:mm:ss"
                $safeRaw = ($cmdInfo.Raw -replace "`r", "<CR>" -replace "`n", "<LF>")
                Write-Host "$time RAW [$safeRaw]" -ForegroundColor White
                Write-Host "$time COMMAND [$($cmdInfo.Command)]" -ForegroundColor White
                if (-not [string]::IsNullOrWhiteSpace($cmdInfo.Argument)) {
                    Write-Host "$time ARGUMENT [$($cmdInfo.Argument)]" -ForegroundColor White
                }

                # Q is a client-side quit command. Close without returning a screen.
                if ($cmdInfo.Command -eq "Q") {
                    Write-Host "$time QUIT REQUEST" -ForegroundColor Yellow
                    break
                }

                $payload = New-Payload -Command $cmdInfo.Command -Argument $cmdInfo.Argument
                $text = $payload.Text
                $screenBytes = Convert-ToC64ScreenBytes -Text $text
                $sparse = Convert-ToSparseRowBytes -ScreenBytes $screenBytes
                $bytes = $sparse.Bytes

                Write-Host "$time PAYLOAD $($payload.Name) $($sparse.Rows) ROWS / $($bytes.Length) BYTES" -ForegroundColor Yellow

                $result = Write-RgpScreenBytes -Stream $stream -Bytes $bytes -Time $time

                if ($result.Complete) {
                    Write-Host "$time WRITE COMPLETE $($result.Sent) BYTES" -ForegroundColor Green
                }
            }
        }
        catch {
            $time = Get-Date -Format "HH:mm:ss"
            Write-Host "$time ERROR $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            $stream.Close()
            $client.Close()
            $time = Get-Date -Format "HH:mm:ss"
            Write-Host "$time CLOSED" -ForegroundColor DarkGray
            Write-Host "$time Waiting for new client..." -ForegroundColor Cyan
        }
    }
}
finally {
    Write-Host "Stopping Parallels RAS Retro Gateway Service..." -ForegroundColor Yellow
    if ($null -ne $script:NextAuthenticatedClient) { $script:NextAuthenticatedClient.Close() }
    $listener.Stop()
    Write-Host "Parallels RAS Retro Gateway Service stopped." -ForegroundColor Green
}
