# BRIDGE OS - local server + terminal session launcher
param(
    [string]$Action = "start",
    [string]$ProjectId = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Port = 8787
$DataFile = Join-Path $Root "bridge-data.json"
$ConfigFile = Join-Path $Root "bridge-config.json"
$script:MetricsCache = $null
$script:MetricsCacheAt = $null
$script:NetlifySitesCache = $null

function Test-ServerUp {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/info" -UseBasicParsing -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

function Get-BridgeData {
    if (-not (Test-Path -LiteralPath $DataFile)) { throw "bridge-data.json not found" }
    $raw = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8
    ConvertFrom-Json $raw
}

function Get-BridgeConfig {
    $cfg = @{
        github = @{ user = "DavidPatlas-AI"; token = "" }
        netlify = @{ token = "" }
        portfolioPath = ""
        metricsCacheSeconds = 300
    }
    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $file = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($file.github) {
                if ($file.github.user) { $cfg.github.user = [string]$file.github.user }
                if ($file.github.token) { $cfg.github.token = [string]$file.github.token }
            }
            if ($file.netlify -and $file.netlify.token) {
                $cfg.netlify.token = [string]$file.netlify.token
            }
            if ($file.portfolioPath) { $cfg.portfolioPath = [string]$file.portfolioPath }
            if ($file.metricsCacheSeconds) { $cfg.metricsCacheSeconds = [int]$file.metricsCacheSeconds }
        } catch { }
    }
    return $cfg
}

function Get-BridgeConfigPublic {
    $cfg = Get-BridgeConfig
    return @{
        ok = $true
        github = @{
            user = [string]$cfg.github.user
            tokenSet = [bool]$cfg.github.token
        }
        netlify = @{ tokenSet = [bool]$cfg.netlify.token }
        portfolioPath = if ($cfg.portfolioPath) { [string]$cfg.portfolioPath } else { (Get-PortfolioPath) }
        metricsCacheSeconds = [int]$cfg.metricsCacheSeconds
        configPath = $ConfigFile
        configExists = (Test-Path -LiteralPath $ConfigFile)
    }
}

function Save-BridgeConfigFromBody([string]$Body) {
    $incoming = $Body | ConvertFrom-Json
    $current = Get-BridgeConfig
    $out = @{
        github = @{
            user = [string]$current.github.user
            token = [string]$current.github.token
        }
        netlify = @{ token = [string]$current.netlify.token }
        portfolioPath = [string]$current.portfolioPath
        metricsCacheSeconds = [int]$current.metricsCacheSeconds
    }
    if ($incoming.github) {
        if ($incoming.github.PSObject.Properties.Name -contains "user" -and $incoming.github.user) {
            $out.github.user = [string]$incoming.github.user
        }
        if ($incoming.github.PSObject.Properties.Name -contains "token") {
            $tok = [string]$incoming.github.token
            if ($tok -and $tok -notmatch '^\*+$') { $out.github.token = $tok }
        }
    }
    if ($incoming.netlify -and $incoming.netlify.PSObject.Properties.Name -contains "token") {
        $tok = [string]$incoming.netlify.token
        if ($tok -and $tok -notmatch '^\*+$') { $out.netlify.token = $tok }
    }
    if ($incoming.portfolioPath) { $out.portfolioPath = [string]$incoming.portfolioPath }
    if ($incoming.metricsCacheSeconds) { $out.metricsCacheSeconds = [int]$incoming.metricsCacheSeconds }
    $json = $out | ConvertTo-Json -Depth 4 -Compress:$false
    [System.IO.File]::WriteAllText($ConfigFile, $json, [System.Text.UTF8Encoding]::new($false))
    $script:MetricsCache = $null
    return @{ ok = $true; path = $ConfigFile }
}

function Test-RecentFilesServer {
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:8082/api/config" -UseBasicParsing -TimeoutSec 2
        return $true
    } catch {
        return $false
    }
}

function Get-BridgeEcosystem {
    $statusMapCandidates = @(
        (Join-Path $env:USERPROFILE "Desktop\מפת סטטוס פרויקטים\מפת סטטוס פרויקטים.html"),
        (Join-Path $env:USERPROFILE "Desktop\מפת סטטוס פרויקטים\index.html"),
        (Join-Path $env:USERPROFILE "Desktop\פרויקטים\מפת סטטוס פרויקטים\מפת סטטוס פרויקטים.html"),
        (Join-Path $env:USERPROFILE "Desktop\פרויקטים\מפת סטטוס פרויקטים\index.html")
    )
    $statusMap = $statusMapCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $statusMap) { $statusMap = $statusMapCandidates[0] }
    return @{
        ok = $true
        version = "2.1"
        bridge = @{ up = $true; port = $Port }
        recentFiles = @{
            up = (Test-RecentFilesServer)
            port = 8082
            url = "http://127.0.0.1:8082/recent-files.html"
        }
        portfolio = @{
            path = (Get-PortfolioPath)
            url = "http://127.0.0.1:8787/"
        }
        statusMap = @{
            exists = (Test-Path -LiteralPath $statusMap)
            path = $statusMap
        }
        guide = @{
            path = (Join-Path $Root "landing.html")
            url = "http://127.0.0.1:$Port/landing.html"
        }
        mcp = @{
            script = (Join-Path $Root "bridge-mcp-server.py")
            config = (Join-Path $Root "mcp-config.json")
        }
    }
}

function Get-BridgeHealth {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $data = Get-BridgeData
    $projects = @()
    foreach ($p in $data.projects) {
        $path = [string]$p.path
        $exists = $path -and (Test-Path -LiteralPath $path)
        $broad = $path -eq $desktop -or $path -eq (Split-Path -Parent $desktop)
        $state = if (-not $exists) { "fail" } elseif ($broad) { "warn" } else { "ok" }
        $projects += @{
            id = [string]$p.id
            name = [string]$p.name
            path = $path
            exists = [bool]$exists
            broad = [bool]$broad
            state = $state
        }
    }

    $toolsDir = Join-Path $desktop "כלים"
    $checks = @(
        @{ name = "קיצור BridgeOS"; path = (Join-Path $desktop "🌉 Bridge OS.bat") },
        @{ name = "כלים / Bridge OS"; path = (Join-Path $toolsDir "Bridge OS.bat") },
        @{ name = "שולחן עבודה מלא"; path = (Join-Path $toolsDir "הפעל שולחן עבודה מלא.bat") },
        @{ name = "Overlay שקוף"; path = (Join-Path $toolsDir "חוטים שקוף.bat") },
        @{ name = "קבצים אחרונים"; path = (Join-Path $desktop "פרויקטים\recent-files-by-project\recent_files_server.py") },
        @{ name = "Tray קבצים"; path = (Join-Path $desktop "פרויקטים\recent-files-by-project\recent_files_tray.pyw") },
        @{ name = "מפת סטטוס"; path = (Join-Path $desktop "פרויקטים\מפת סטטוס פרויקטים\מפת סטטוס פרויקטים.html") }
    )
    $toolRows = @()
    foreach ($c in $checks) {
        $exists = Test-Path -LiteralPath $c.path
        $toolRows += @{
            name = [string]$c.name
            path = [string]$c.path
            exists = [bool]$exists
            state = if ($exists) { "ok" } else { "fail" }
        }
    }

    $cfg = Get-BridgeConfigPublic
    $eco = Get-BridgeEcosystem
    $projectFail = @($projects | Where-Object { $_.state -eq "fail" }).Count
    $projectWarn = @($projects | Where-Object { $_.state -eq "warn" }).Count
    $toolFail = @($toolRows | Where-Object { $_.state -eq "fail" }).Count
    $recentUp = [bool]$eco.recentFiles.up

    return @{
        ok = ($projectFail -eq 0 -and $toolFail -eq 0)
        generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        root = $Root
        server = @{ ok = $true; port = $Port; root = $Root }
        summary = @{
            projects = @($projects).Count
            projectWarnings = $projectWarn
            projectFailures = $projectFail
            tools = @($toolRows).Count
            toolFailures = $toolFail
            recentFiles = $recentUp
            statusMap = [bool]$eco.statusMap.exists
            mcp = (Test-Path -LiteralPath (Join-Path $Root "mcp-config.json"))
            netlifyToken = [bool]$cfg.netlify.tokenSet
            githubToken = [bool]$cfg.github.tokenSet
        }
        projects = $projects
        tools = $toolRows
        ecosystem = $eco
        reportPath = (Join-Path $Root "BRIDGE_HEALTH_REPORT.md")
    }
}

function Get-ProjectRecentFiles([string]$ProjectId, [int]$Days = 7, [int]$Limit = 12) {
    if (-not (Test-RecentFilesServer)) {
        return @{ ok = $false; error = "recent-files server not running (port 8082)" }
    }
    $data = Get-BridgeData
    $proj = Get-Project $data $ProjectId
    if (-not $proj) { return @{ ok = $false; error = "project not found" } }
    $projPath = [string]$proj.path
    if (-not $projPath) { return @{ ok = $false; error = "no project path" } }
    $normPath = $projPath.TrimEnd('\', '/').ToLower()
    try {
        $url = "http://127.0.0.1:8082/api/files?days=$Days&limit=500&refresh=0"
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 5
        $files = @()
        foreach ($f in $resp.files) {
            $fp = ([string]$f.path).ToLower().Replace('/', '\')
            if ($fp.StartsWith($normPath)) { $files += $f }
            if ($files.Count -ge $Limit) { break }
        }
        return @{
            ok = $true
            project = $ProjectId
            path = $projPath
            days = $Days
            count = $files.Count
            files = $files
            recentFilesUrl = "http://127.0.0.1:8082/recent-files.html"
        }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Get-NetlifySites([string]$Token) {
    if ($script:NetlifySitesCache) { return $script:NetlifySitesCache }
    $headers = @{ Authorization = "Bearer $Token" }
    $sites = Invoke-RestMethod -Uri "https://api.netlify.com/api/v1/sites?per_page=100" `
        -Headers $headers -TimeoutSec 15
    $script:NetlifySitesCache = $sites
    return $sites
}

function Get-NetlifyHostname([string]$Url) {
    try { return ([Uri]$Url).Host.ToLower() } catch { return $null }
}

function Find-NetlifySite($Sites, [string]$HostName) {
    if (-not $HostName) { return $null }
    $sub = $HostName -replace '\.netlify\.app$', ''
    foreach ($s in $Sites) {
        $ssl = ([string]$s.ssl_url).ToLower()
        $url = ([string]$s.url).ToLower()
        $dom = ([string]$s.custom_domain).ToLower()
        $name = ([string]$s.name).ToLower()
        if ($ssl -like "*$HostName*" -or $url -like "*$HostName*" -or $dom -eq $HostName) { return $s }
        if ($name -eq $sub) { return $s }
        if ($s.domain_aliases) {
            foreach ($a in $s.domain_aliases) {
                if ([string]$a -eq $HostName) { return $s }
            }
        }
    }
    return $null
}

function Get-NetlifyPageviews([string]$SiteId, [string]$Token, [int]$Days) {
    $headers = @{ Authorization = "Bearer $Token" }
    $from = (Get-Date).AddDays(-1 * $Days).ToString("yyyy-MM-dd")
    $to = (Get-Date).ToString("yyyy-MM-dd")
    $pvUrl = "https://api.netlify.com/api/v1/sites/$SiteId/analytics/pageviews?from=$from&to=$to"
    try {
        $pv = Invoke-RestMethod -Uri $pvUrl -Headers $headers -TimeoutSec 12
        if ($pv -and $pv.data) {
            $total = 0
            foreach ($row in $pv.data) {
                if ($row.PSObject.Properties.Name -contains "value") { $total += [int]$row.value }
                elseif ($row.PSObject.Properties.Name -contains "pageviews") { $total += [int]$row.pageviews }
            }
            return @{ ok = $true; total = $total; days = $Days }
        }
        if ($pv -and $pv.PSObject.Properties.Name -contains "pageviews") {
            return @{ ok = $true; total = [int]$pv.pageviews; days = $Days }
        }
        return @{ ok = $true; total = 0; days = $Days }
    } catch {
        $msg = $_.Exception.Message
        $disabled = $msg -match '403|404|402|analytics|not enabled|not found'
        return @{ ok = $false; error = $msg; analyticsDisabled = $disabled; days = $Days }
    }
}

function Get-NetlifyMetrics([string]$DemoUrl, [string]$Token) {
    if (-not $Token -or -not $DemoUrl) {
        return @{ ok = $false; skipped = $true; reason = "no token" }
    }
    try {
        $hostName = Get-NetlifyHostname $DemoUrl
        if (-not $hostName) { return @{ ok = $false; error = "bad url" } }
        $sites = Get-NetlifySites $Token
        $site = Find-NetlifySite $sites $hostName
        if (-not $site) { return @{ ok = $false; error = "site not found"; host = $hostName } }

        $headers = @{ Authorization = "Bearer $Token" }
        $deploys = Invoke-RestMethod -Uri "https://api.netlify.com/api/v1/sites/$($site.id)/deploys?per_page=1" `
            -Headers $headers -TimeoutSec 12
        $deploy = $deploys[0]
        $result = @{
            ok = $true
            site = [string]$site.name
            siteId = [string]$site.id
            url = [string]$site.ssl_url
            host = $hostName
            lastDeploy = @{
                date = [string]$deploy.created_at
                state = [string]$deploy.state
            }
            pageviews = $null
            pageviews7d = $null
            pageviews30d = $null
            viewsPeriod = "30d"
            analyticsEnabled = $null
        }

        $pv7 = Get-NetlifyPageviews $site.id $Token 7
        $pv30 = Get-NetlifyPageviews $site.id $Token 30
        if ($pv7.ok) {
            $result.pageviews7d = $pv7.total
        }
        if ($pv30.ok) {
            $result.pageviews30d = $pv30.total
            $result.pageviews = $pv30.total
            $result.analyticsEnabled = $true
        } elseif ($pv7.ok) {
            $result.pageviews = $pv7.total
            $result.viewsPeriod = "7d"
            $result.analyticsEnabled = $true
        } else {
            $disabled = ($pv30.analyticsDisabled -or $pv7.analyticsDisabled)
            $result.analyticsEnabled = -not $disabled
            if (-not $disabled) { $result.analyticsError = $pv30.error }
        }
        return $result
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Get-NetlifySummary {
    $cfg = Get-BridgeConfig
    $token = [string]$cfg.netlify.token
    if (-not $token) {
        return @{
            ok = $true
            configured = $false
            hint = "Add netlify.token to bridge-config.json (Netlify > User settings > Personal access tokens)"
        }
    }
    $data = Get-BridgeData
    $sites = @()
    $total7 = 0
    $total30 = 0
    $withAnalytics = 0
    try {
        $allSites = Get-NetlifySites $token
        foreach ($p in $data.projects) {
            $demo = ""
            if ($p.PSObject.Properties.Name -contains "demo") { $demo = [string]$p.demo }
            if (-not $demo -or $demo -notmatch 'netlify\.app') { continue }
            $nf = Get-NetlifyMetrics $demo $token
            if (-not $nf.ok) { continue }
            if ($null -ne $nf.pageviews7d) { $total7 += [int]$nf.pageviews7d }
            if ($null -ne $nf.pageviews30d) { $total30 += [int]$nf.pageviews30d }
            elseif ($null -ne $nf.pageviews) { $total30 += [int]$nf.pageviews }
            if ($nf.analyticsEnabled) { $withAnalytics++ }
            $sites += @{
                projectId = [string]$p.id
                name = [string]$p.name
                site = $nf.site
                host = $nf.host
                pageviews7d = $nf.pageviews7d
                pageviews30d = $nf.pageviews30d
                analyticsEnabled = $nf.analyticsEnabled
                lastDeploy = $nf.lastDeploy
            }
        }
        return @{
            ok = $true
            configured = $true
            accountSites = @($allSites).Count
            linkedProjects = $sites.Count
            withAnalytics = $withAnalytics
            totalPageviews7d = $total7
            totalPageviews30d = $total30
            sites = $sites
        }
    } catch {
        return @{ ok = $false; configured = $true; error = $_.Exception.Message }
    }
}

function Get-GitHubRepoName([string]$Github) {
    if (-not $Github) { return $null }
    if ($Github -match 'github\.com/([^/]+/[^/]+)') {
        return ($Matches[1] -replace '\.git$', '').TrimEnd('/')
    }
    if ($Github -match '^[^/]+/[^/]+$') { return $Github }
    return $null
}

function Get-GitHubHeaders([string]$Token) {
    $h = @{ "User-Agent" = "Bridge-OS/2.1" }
    if ($Token) { $h["Authorization"] = "Bearer $Token" }
    return $h
}

function Get-GitHubMetrics([string]$Repo, [string]$Token) {
    $headers = Get-GitHubHeaders $Token
    try {
        $commits = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits?per_page=1" `
            -Headers $headers -TimeoutSec 12
        $info = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo" `
            -Headers $headers -TimeoutSec 12
        $msg = [string]$commits[0].commit.message
        $msg = ($msg -split '(\r?\n)')[0].Trim()
        if ($msg.Length -gt 72) { $msg = $msg.Substring(0, 72) + "..." }
        return @{
            ok = $true
            repo = $Repo
            url = [string]$info.html_url
            stars = [int]$info.stargazers_count
            openIssues = [int]$info.open_issues_count
            lastCommit = @{
                sha = [string]$commits[0].sha.Substring(0, 7)
                date = [string]$commits[0].commit.author.date
                message = $msg
            }
        }
    } catch {
        return @{ ok = $false; repo = $Repo; error = $_.Exception.Message }
    }
}

function Test-DemoUrl([string]$Url) {
    if (-not $Url) { return @{ ok = $false; live = $false; error = "no url" } }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 10
        $sw.Stop()
        return @{
            ok = $true
            live = ($r.StatusCode -lt 400)
            status = [int]$r.StatusCode
            ms = [int]$sw.ElapsedMilliseconds
            url = $Url
        }
    } catch {
        try {
            $r = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec 12
            $sw.Stop()
            return @{
                ok = $true
                live = ($r.StatusCode -lt 400)
                status = [int]$r.StatusCode
                ms = [int]$sw.ElapsedMilliseconds
                url = $Url
            }
        } catch {
            $sw.Stop()
            return @{
                ok = $false
                live = $false
                ms = [int]$sw.ElapsedMilliseconds
                url = $Url
                error = $_.Exception.Message
            }
        }
    }
}

function Get-BridgeMetrics([switch]$Force) {
    $cfg = Get-BridgeConfig
    $ttl = [math]::Max(60, $cfg.metricsCacheSeconds)
    if (-not $Force -and $script:MetricsCache -and $script:MetricsCacheAt) {
        $age = ((Get-Date) - $script:MetricsCacheAt).TotalSeconds
        if ($age -lt $ttl) { return $script:MetricsCache }
    }

    $data = Get-BridgeData
    $token = $cfg.github.token
    $projects = @{}

    foreach ($p in $data.projects) {
        $entry = @{ id = [string]$p.id }
        $ghField = $null
        if ($p.PSObject.Properties.Name -contains "github") { $ghField = [string]$p.github }
        if ($ghField) {
            $repo = Get-GitHubRepoName $ghField
            if (-not $repo -and $cfg.github.user) { $repo = "$($cfg.github.user)/$ghField" }
            if ($repo) { $entry.github = Get-GitHubMetrics $repo $token }
        }
        $demoField = $null
        if ($p.PSObject.Properties.Name -contains "demo") { $demoField = [string]$p.demo }
        if ($demoField) {
            $entry.demo = Test-DemoUrl $demoField
            if ($cfg.netlify.token -and $demoField -match 'netlify\.app') {
                $entry.netlify = Get-NetlifyMetrics $demoField $cfg.netlify.token
            }
        }
        $projects[[string]$p.id] = $entry
    }

    $result = @{
        ok = $true
        version = "2.1"
        updated = (Get-Date).ToString("o")
        cacheSeconds = $ttl
        projects = $projects
    }
    $script:MetricsCache = $result
    $script:MetricsCacheAt = Get-Date
    return $result
}

function Write-CompartmentMap([object]$Data) {
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# COMPARTMENT MAP - BRIDGE OS")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Updated: $now")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Worlds")
    foreach ($w in $Data.worlds) {
        [void]$sb.AppendLine("- **$($w.name)** ($($w.id))")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Active Projects")
    foreach ($p in $Data.projects) {
        $pct = [math]::Round([double]$p.progress * 100)
        [void]$sb.AppendLine("### $($p.name) [$($p.status)] $pct%")
        [void]$sb.AppendLine("- Goal: $($p.goal)")
        [void]$sb.AppendLine("- Path: $($p.path)")
        if ($p.PSObject.Properties.Name -contains "demo" -and $p.demo) {
            [void]$sb.AppendLine("- Demo: $($p.demo)")
        }
        if ($p.PSObject.Properties.Name -contains "github" -and $p.github) {
            [void]$sb.AppendLine("- GitHub: $($p.github)")
        }
        [void]$sb.AppendLine("- Thread: $($p.thread -join ' <-> ')")
        $next = $p.workOrder | Where-Object { -not $_.done } | Select-Object -First 1
        if ($next) { [void]$sb.AppendLine("- Next: $($next.task)") }
        if ($p.questions -and $p.questions.Count -gt 0) {
            [void]$sb.AppendLine("- Questions:")
            foreach ($q in $p.questions) { [void]$sb.AppendLine("  - $q") }
        }
        [void]$sb.AppendLine("")
    }
    $mapPath = Join-Path $Root "COMPARTMENT_MAP.md"
    [System.IO.File]::WriteAllText($mapPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

function Write-BridgeExport([object]$Data) {
    $items = @()
    foreach ($p in $Data.projects) {
        $done = @($p.workOrder | Where-Object { $_.done }).Count
        $total = @($p.workOrder).Count
        $next = $p.workOrder | Where-Object { -not $_.done } | Select-Object -First 1
        $items += @{
            id = [string]$p.id
            name = [string]$p.name
            goal = [string]$p.goal
            status = [string]$p.status
            progress = [math]::Round([double]$p.progress * 100)
            github = if ($p.PSObject.Properties.Name -contains "github") { [string]$p.github } else { "" }
            demo = if ($p.PSObject.Properties.Name -contains "demo") { [string]$p.demo } else { "" }
            thread = @($p.thread)
            nextTask = if ($next) { [string]$next.task } else { "" }
            tasksDone = $done
            tasksTotal = $total
        }
    }
    $export = @{
        version = "2.1"
        updated = (Get-Date).ToString("o")
        source = "BRIDGE OS"
        projects = $items
        worlds = @($Data.worlds | ForEach-Object { @{ id = $_.id; name = $_.name } })
    }
    $exportPath = Join-Path $Root "bridge-export.json"
    [System.IO.File]::WriteAllText($exportPath, ($export | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
}

function Write-BridgeMcp([object]$Data) {
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"
    $mcpPy = Join-Path $Root "bridge-mcp-server.py"
    $mcpCfg = Join-Path $Root "mcp-config.json"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# BRIDGE MCP - Claude Code / Cursor')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("> Updated: $now - http://127.0.0.1:$Port/")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## MCP server (stdio)')
    [void]$sb.AppendLine('1. pip install -r requirements-mcp.txt  (Python 3.12: py -3.12 -m pip install mcp)')
    [void]$sb.AppendLine('2. Start Bridge OS: run shulchan-avoda.bat from Desktop')
    [void]$sb.AppendLine("3. Add to Cursor/Claude MCP settings from: $mcpCfg")
    [void]$sb.AppendLine("4. Server script: $mcpPy")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('### MCP tools')
    [void]$sb.AppendLine('- bridge_list_projects')
    [void]$sb.AppendLine('- bridge_open_terminal(project_id)')
    [void]$sb.AppendLine('- bridge_dashboard')
    [void]$sb.AppendLine('- bridge_metrics(refresh)')
    [void]$sb.AppendLine('- bridge_netlify(refresh)')
    [void]$sb.AppendLine('- bridge_sync_portfolio(direction)')
    [void]$sb.AppendLine('- bridge_get_project(project_id)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('### MCP resources')
    [void]$sb.AppendLine('- bridge://data | bridge://map | bridge://export | bridge://mcp')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Files to read')
    [void]$sb.AppendLine('- bridge-data.json - full state')
    [void]$sb.AppendLine('- COMPARTMENT_MAP.md - active projects summary')
    [void]$sb.AppendLine('- bridge-export.json - portfolio-friendly export')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## HTTP API (local)')
    [void]$sb.AppendLine('- GET /api/mcp - machine manifest')
    [void]$sb.AppendLine('- GET /api/dashboard - stats')
    [void]$sb.AppendLine('- GET /api/metrics - GitHub + Netlify deploy + pageviews')
    [void]$sb.AppendLine('- GET /api/netlify - Analytics summary (7d/30d totals)')
    [void]$sb.AppendLine('- GET /open/{projectId} - terminal + BRIDGE_SESSION.md')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Projects')
    foreach ($p in $Data.projects) {
        $pct = [math]::Round([double]$p.progress * 100)
        [void]$sb.AppendLine("- **$($p.name)** ($($p.id)) $pct% - open: /open/$($p.id)")
    }
    $mcpPath = Join-Path $Root "BRIDGE_MCP.md"
    [System.IO.File]::WriteAllText($mcpPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
}

function Get-BridgeDashboard {
    $cfg = Get-BridgeConfig
    $data = Get-BridgeData
    $metrics = Get-BridgeMetrics
    $live = 0
    $totalPv30 = 0
    $netlifyLinked = 0
    foreach ($p in $data.projects) {
        $projId = [string]$p.id
        $pm = $metrics.projects[$projId]
        if ($pm -and $pm.demo -and $pm.demo.live) { $live++ }
        if ($pm -and $pm.netlify -and $pm.netlify.ok) {
            $netlifyLinked++
            if ($null -ne $pm.netlify.pageviews30d) { $totalPv30 += [int]$pm.netlify.pageviews30d }
            elseif ($null -ne $pm.netlify.pageviews) { $totalPv30 += [int]$pm.netlify.pageviews }
        }
    }
    return @{
        ok = $true
        version = "2.1"
        updated = (Get-Date).ToString("o")
        worlds = @($data.worlds).Count
        threads = @($data.threads).Count
        projects = @($data.projects).Count
        active = @($data.projects | Where-Object { $_.status -in @("running", "thinking") }).Count
        waiting = @($data.projects | Where-Object { $_.status -eq "waiting" }).Count
        done = @($data.projects | Where-Object { $_.status -eq "done" }).Count
        liveSites = $live
        withDemo = @($data.projects | Where-Object { $_.PSObject.Properties.Name -contains "demo" -and $_.demo }).Count
        netlifyConfigured = [bool]$cfg.netlify.token
        netlifyLinked = $netlifyLinked
        totalPageviews30d = $totalPv30
    }
}

function Get-McpManifest {
    $data = Get-BridgeData
    $tools = @(
        @{
            name = "bridge_list_projects"
            description = "List all Bridge OS projects with status and progress"
            endpoint = "GET /api/data"
        },
        @{
            name = "bridge_open_terminal"
            description = "Open Windows Terminal + Claude session for a project"
            endpoint = "GET /open/{id}"
            example = "http://127.0.0.1:$Port/open/p5"
        },
        @{
            name = "bridge_dashboard"
            description = "Summary stats: active, waiting, live sites"
            endpoint = "GET /api/dashboard"
        },
        @{
            name = "bridge_metrics"
            description = "GitHub commits, Netlify deploy, live HTTP check"
            endpoint = "GET /api/metrics"
        },
        @{
            name = "bridge_netlify"
            description = "Netlify Analytics pageviews 7d/30d per linked project"
            endpoint = "GET /api/netlify"
        },
        @{
            name = "bridge_sync_portfolio"
            description = "Bidirectional sync github/demo/desc/status with portfolio.html (direction=both|from|to)"
            endpoint = "POST /api/sync-portfolio?direction=both"
        },
        @{
            name = "bridge_get_project"
            description = "Full details for one project by id"
            endpoint = "GET /api/data (filter by id)"
        }
    )
    $resources = @(
        @{ uri = "bridge://data"; path = "bridge-data.json"; mime = "application/json" },
        @{ uri = "bridge://map"; path = "COMPARTMENT_MAP.md"; mime = "text/markdown" },
        @{ uri = "bridge://export"; path = "bridge-export.json"; mime = "application/json" },
        @{ uri = "bridge://mcp"; path = "BRIDGE_MCP.md"; mime = "text/markdown" }
    )
    return @{
        name = "bridge-os"
        version = "2.1"
        port = $Port
        baseUrl = "http://127.0.0.1:$Port"
        mcpServer = "bridge-mcp-server.py"
        mcpConfig = "mcp-config.json"
        transport = "stdio"
        tools = $tools
        resources = $resources
        projects = @($data.projects | ForEach-Object {
            @{
                id = $_.id
                name = $_.name
                path = $_.path
                open = "http://127.0.0.1:$Port/open/$($_.id)"
            }
        })
    }
}

function Save-BridgeData([string]$Json) {
    $parsed = $Json | ConvertFrom-Json
    if (-not $parsed.worlds -or -not $parsed.projects) {
        throw "Invalid data: worlds and projects required"
    }
    [System.IO.File]::WriteAllText($DataFile, $Json, [System.Text.UTF8Encoding]::new($false))
    Write-CompartmentMap $parsed
    Write-BridgeExport $parsed
    Write-BridgeMcp $parsed
    Sync-TerminalBats
}

function Get-Project([object]$Data, [string]$Id) {
    $Data.projects | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Build-SessionMarkdown($Proj, $Data) {
    $wmap = @{}
    foreach ($w in $Data.worlds) { $wmap[$w.id] = $w }
    $w1 = $wmap[$Proj.thread[0]].name
    $w2 = $wmap[$Proj.thread[1]].name
    $done = ($Proj.workOrder | Where-Object { $_.done } | ForEach-Object { "- [x] $($_.task)" }) -join [Environment]::NewLine
    $pend = ($Proj.workOrder | Where-Object { -not $_.done } | ForEach-Object { "- [ ] $($_.task)" }) -join [Environment]::NewLine

    $qa = ""
    if ($Proj.answers -and ($Proj.answers | Get-Member -MemberType NoteProperty)) {
        $qa = ($Proj.answers.PSObject.Properties | ForEach-Object {
            "**Q:** $($_.Name)" + [Environment]::NewLine + "**A:** $($_.Value)"
        }) -join ([Environment]::NewLine + [Environment]::NewLine)
    }

    $openQ = @($Proj.questions | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    $pct = [math]::Round([double]$Proj.progress * 100)
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# BRIDGE SESSION - $($Proj.name)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> BRIDGE OS - $now")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Goal")
    [void]$sb.AppendLine([string]$Proj.goal)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Bridge")
    [void]$sb.AppendLine("$w1 <-> $w2")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Progress")
    [void]$sb.AppendLine("$pct%")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Done")
    if ($done) { [void]$sb.AppendLine($done) }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Next")
    if ($pend) { [void]$sb.AppendLine($pend) }
    if ($qa) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Context")
        [void]$sb.AppendLine($qa)
    }
    if ($openQ) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Open questions")
        [void]$sb.AppendLine($openQ)
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Insight")
    [void]$sb.AppendLine([string]$Proj.insight)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Paste into Claude Code:")
    [void]$sb.AppendLine("Read BRIDGE_SESSION.md and continue the next unchecked task.")
    $sb.ToString()
}

function Open-BridgeFolder([string]$Id) {
    $data = Get-BridgeData
    $proj = Get-Project $data $Id
    if (-not $proj) { throw "Project not found: $Id" }
    $path = [string]$proj.path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        $path = $Root
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList @($path) | Out-Null
    return @{ ok = $true; project = $proj.id; path = $path }
}

function Open-BridgeSession([string]$Id) {
    $data = Get-BridgeData
    $proj = Get-Project $data $Id
    if (-not $proj) { throw "Project not found: $Id" }

    $path = [string]$proj.path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        $path = $Root
    }

    $sessionMd = Build-SessionMarkdown $proj $data
    $sessionPath = Join-Path $path "BRIDGE_SESSION.md"
    [System.IO.File]::WriteAllText($sessionPath, $sessionMd, [System.Text.UTF8Encoding]::new($false))

    $prompt = "Read BRIDGE_SESSION.md and continue project: $($proj.name)"
    Set-Clipboard -Value $prompt

    $claude = Get-Command claude -ErrorAction SilentlyContinue
    $wt = Get-Command wt -ErrorAction SilentlyContinue
    $escapedPath = $sessionPath.Replace("'", "''")

    if ($wt) {
        $inner = "Write-Host 'BRIDGE OS - $($proj.name)' -ForegroundColor Cyan; " +
                 "Get-Content -LiteralPath '$escapedPath' -Encoding UTF8 | Select-Object -First 50; " +
                 "Write-Host ''; Write-Host 'Prompt copied to clipboard' -ForegroundColor Yellow"
        if ($claude) { $inner += "; claude" }
        Start-Process -FilePath "wt.exe" -ArgumentList @(
            "-w", "0", "nt", "-d", $path,
            "powershell.exe", "-NoExit", "-NoProfile", "-Command", $inner
        ) | Out-Null
    } else {
        Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoExit", "-NoProfile", "-Command",
            "Set-Location -LiteralPath '$path'; Get-Content -LiteralPath '$escapedPath' -Encoding UTF8"
        ) | Out-Null
    }

    return @{
        ok = $true
        project = $proj.id
        path = $path
        session = $sessionPath
        prompt = $prompt
    }
}

function Send-Response([System.Net.HttpListenerResponse]$Res, [int]$Code, [string]$Body, [string]$ContentType) {
    if (-not $ContentType) { $ContentType = "application/json; charset=utf-8" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Res.StatusCode = $Code
    $Res.ContentType = $ContentType
    $Res.AddHeader("Access-Control-Allow-Origin", "*")
    $Res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $Res.AddHeader("Access-Control-Allow-Headers", "Content-Type")
    $Res.ContentLength64 = $bytes.Length
    $Res.OutputStream.Write($bytes, 0, $bytes.Length)
    $Res.Close()
}

function Send-File([System.Net.HttpListenerResponse]$Res, [string]$FilePath) {
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Send-Response $Res 404 '{"error":"not found"}'
        return
    }
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $mime = switch ($ext) {
        ".html" { "text/html; charset=utf-8" }
        ".css"  { "text/css; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".js"   { "application/javascript; charset=utf-8" }
        ".png"  { "image/png" }
        ".jpg"  { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".webp" { "image/webp" }
        ".ico"  { "image/x-icon" }
        ".zip"  { "application/zip" }
        ".txt"  { "text/plain; charset=utf-8" }
        default { "application/octet-stream" }
    }
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Res.StatusCode = 200
    $Res.ContentType = $mime
    $Res.AddHeader("Access-Control-Allow-Origin", "*")
    $Res.ContentLength64 = $bytes.Length
    $Res.OutputStream.Write($bytes, 0, $bytes.Length)
    $Res.Close()
}

function Sync-TerminalBats {
    $data = Get-BridgeData
    $termDir = Join-Path $Root "terminals"
    if (-not (Test-Path -LiteralPath $termDir)) {
        New-Item -ItemType Directory -Path $termDir -Force | Out-Null
    }
    foreach ($p in $data.projects) {
        $safeName = $p.id
        $batPath = Join-Path $termDir "$safeName.bat"
        $lines = @(
            "@echo off"
            "chcp 65001 >nul"
            "cd /d `"%~dp0..`""
            "powershell -ExecutionPolicy Bypass -NoProfile -File `"%~dp0..\bridge.ps1`" open $safeName"
            "pause"
        )
        [System.IO.File]::WriteAllText($batPath, ($lines -join [Environment]::NewLine), [System.Text.Encoding]::ASCII)
    }
}

function Invoke-BridgeHttpContext([System.Net.HttpListenerContext]$Context) {
    $req = $Context.Request
    $res = $Context.Response
    $reqPath = $req.Url.LocalPath

    try {
        if ($req.HttpMethod -eq "OPTIONS") {
            Send-Response $res 200 ""
            return
        }

        if ($reqPath -match "^/open/([^/]+)$") {
            $id = $Matches[1]
            $result = Open-BridgeSession $id
            Send-Response $res 200 ($result | ConvertTo-Json -Compress)
            return
        }

        if ($reqPath -match "^/api/folder/([^/]+)$" -and $req.HttpMethod -eq "GET") {
            $id = $Matches[1]
            $result = Open-BridgeFolder $id
            Send-Response $res 200 ($result | ConvertTo-Json -Compress)
            return
        }

        if ($reqPath -eq "/api/sync-portfolio/preview" -and $req.HttpMethod -eq "GET") {
            $direction = $req.QueryString["direction"]
            if (-not $direction) { $direction = "both" }
            $preview = Get-PortfolioSyncPreview $direction
            Send-Response $res 200 ($preview | ConvertTo-Json -Depth 6 -Compress)
            return
        }

        if ($reqPath -eq "/api/info" -and $req.HttpMethod -eq "GET") {
            $cfg = Get-BridgeConfig
            $info = @{
                root = $Root
                port = $Port
                version = "2.1"
                portfolio = [bool](Get-PortfolioPath)
                netlify = [bool]$cfg.netlify.token
            } | ConvertTo-Json -Compress
            Send-Response $res 200 $info
            return
        }

        if ($reqPath -eq "/api/metrics" -and $req.HttpMethod -eq "GET") {
            $force = $req.QueryString["refresh"] -eq "1"
            if ($force) { $script:NetlifySitesCache = $null }
            $metrics = Get-BridgeMetrics -Force:$force
            Send-Response $res 200 ($metrics | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        if ($reqPath -eq "/api/netlify" -and $req.HttpMethod -eq "GET") {
            $force = $req.QueryString["refresh"] -eq "1"
            if ($force) { $script:NetlifySitesCache = $null }
            $summary = Get-NetlifySummary
            Send-Response $res 200 ($summary | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        if ($reqPath -eq "/api/portfolio" -and $req.HttpMethod -eq "GET") {
            $catalog = Get-PortfolioCatalog | Where-Object { $_.status -eq "live" -and $_.demo }
            $payload = @{
                ok = $true
                path = (Get-PortfolioPath)
                count = @($catalog).Count
                items = $catalog
            } | ConvertTo-Json -Depth 6 -Compress
            Send-Response $res 200 $payload
            return
        }

        if ($reqPath -eq "/api/sync-portfolio" -and $req.HttpMethod -eq "POST") {
            $direction = $req.QueryString["direction"]
            if (-not $direction) { $direction = "both" }
            $result = Sync-PortfolioBidirectional $direction
            Send-Response $res 200 ($result | ConvertTo-Json -Depth 6 -Compress)
            return
        }

        if ($reqPath -eq "/api/ecosystem" -and $req.HttpMethod -eq "GET") {
            $eco = Get-BridgeEcosystem
            Send-Response $res 200 ($eco | ConvertTo-Json -Depth 6 -Compress)
            return
        }

        if ($reqPath -eq "/api/health" -and $req.HttpMethod -eq "GET") {
            $health = Get-BridgeHealth
            Send-Response $res 200 ($health | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        if ($reqPath -eq "/api/config" -and $req.HttpMethod -eq "GET") {
            $cfg = Get-BridgeConfigPublic
            Send-Response $res 200 ($cfg | ConvertTo-Json -Compress)
            return
        }

        if ($reqPath -eq "/api/config" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $saved = Save-BridgeConfigFromBody $body
            Send-Response $res 200 ($saved | ConvertTo-Json -Compress)
            return
        }

        if ($reqPath -match "^/api/recent/([^/]+)$" -and $req.HttpMethod -eq "GET") {
            $projId = $Matches[1]
            $days = 7
            if ($req.QueryString["days"]) { $days = [int]$req.QueryString["days"] }
            $recent = Get-ProjectRecentFiles $projId $days 12
            Send-Response $res 200 ($recent | ConvertTo-Json -Depth 6 -Compress)
            return
        }

        if ($reqPath -eq "/api/dashboard" -and $req.HttpMethod -eq "GET") {
            $dash = Get-BridgeDashboard
            Send-Response $res 200 ($dash | ConvertTo-Json -Compress)
            return
        }

        if ($reqPath -eq "/api/mcp" -and $req.HttpMethod -eq "GET") {
            $mcp = Get-McpManifest
            Send-Response $res 200 ($mcp | ConvertTo-Json -Depth 8 -Compress)
            return
        }

        if ($reqPath -eq "/api/export" -and $req.HttpMethod -eq "GET") {
            $exportPath = Join-Path $Root "bridge-export.json"
            if (-not (Test-Path -LiteralPath $exportPath)) {
                $data = Get-BridgeData
                Write-BridgeExport $data
            }
            Send-File $res $exportPath
            return
        }

        if ($reqPath -eq "/api/data" -and $req.HttpMethod -eq "GET") {
            $json = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8
            Send-Response $res 200 $json
            return
        }

        if ($reqPath -eq "/api/data" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            Save-BridgeData $body
            Send-Response $res 200 '{"ok":true}'
            return
        }

        if ($reqPath -eq "/" -or $reqPath -eq "/index.html") {
            Send-File $res (Join-Path $Root "index.html")
            return
        }

        if ($reqPath -eq "/help" -or $reqPath -eq "/guide" -or $reqPath -eq "/landing") {
            Send-File $res (Join-Path $Root "landing.html")
            return
        }

        if ($reqPath -match "^/lib/(.+)$") {
            $libPath = Join-Path $Root ("lib\" + $Matches[1].Replace("/", "\"))
            if (Test-Path -LiteralPath $libPath) {
                Send-File $res $libPath
                return
            }
        }

        $rel = $reqPath.TrimStart("/").Replace("/", [IO.Path]::DirectorySeparatorChar)
        $filePath = Join-Path $Root $rel
        if (Test-Path -LiteralPath $filePath) {
            Send-File $res $filePath
            return
        }

        Send-Response $res 404 '{"error":"not found"}'
    } catch {
        $msg = $_.Exception.Message -replace '"', "'"
        Send-Response $res 500 "{`"error`":`"$msg`"}"
    }
}

function Start-BridgeServer([bool]$OpenBrowser) {
    if (Test-ServerUp) {
        Write-Host "Server already running on port $Port" -ForegroundColor Yellow
        if ($OpenBrowser) { Start-Process "http://127.0.0.1:$Port/" }
        return
    }

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    try {
        $listener.Start()
    } catch {
        Write-Host "Cannot start server on port $Port. Close other Bridge OS windows." -ForegroundColor Red
        throw
    }

    Write-Host "BRIDGE OS -> http://127.0.0.1:$Port/" -ForegroundColor Green
    Write-Host "Guide     -> http://127.0.0.1:$Port/landing.html" -ForegroundColor Cyan
    if ($OpenBrowser) {
        Start-Process "http://127.0.0.1:$Port/"
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, 8)
    $pool.Open()
    $bridgeScript = $PSCommandPath
    $active = New-Object System.Collections.ArrayList

    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript({
            param($Context, $ScriptPath)
            $script:BridgeLibOnly = $true
            . $ScriptPath
            Invoke-BridgeHttpContext -Context $Context
        }).AddArgument($ctx).AddArgument($bridgeScript)
        $handle = $ps.BeginInvoke()
        [void]$active.Add(@{ PS = $ps; Handle = $handle })

        for ($i = $active.Count - 1; $i -ge 0; $i--) {
            $item = $active[$i]
            if ($item.Handle.IsCompleted) {
                try { $null = $item.PS.EndInvoke($item.Handle) } catch { }
                $item.PS.Dispose()
                $active.RemoveAt($i)
            }
        }
    }
}

. (Join-Path $PSScriptRoot "bridge-portfolio.ps1")

if ($script:BridgeLibOnly) { return }

if ($Action -eq "sync") {
    $data = Get-BridgeData
    Write-CompartmentMap $data
    Write-BridgeExport $data
    Write-BridgeMcp $data
    Sync-TerminalBats
    Write-Host "Terminal shortcuts synced." -ForegroundColor Green
    exit 0
}

if ($Action -eq "open" -and $ProjectId) {
    $r = Open-BridgeSession $ProjectId
    Write-Host "Opened: $($r.project) -> $($r.path)" -ForegroundColor Cyan
    exit 0
}

if ($Action -eq "serve") {
    Start-BridgeServer $false
    exit 0
}

if ($Action -eq "browser") {
    Start-Process "http://127.0.0.1:$Port/"
    exit 0
}

$data = Get-BridgeData
Write-CompartmentMap $data
Sync-TerminalBats
Start-BridgeServer $true
