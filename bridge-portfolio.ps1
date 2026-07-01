# Portfolio sync helpers (dot-sourced from bridge.ps1)

function Get-PortfolioPath {
    $cfg = Get-BridgeConfig
    if ($cfg.portfolioPath -and (Test-Path -LiteralPath $cfg.portfolioPath)) {
        return $cfg.portfolioPath
    }
    $found = Get-ChildItem (Join-Path $env:USERPROFILE "Desktop") -Filter "portfolio.html" `
        -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-PortfolioField([string]$Chunk, [string]$Pattern) {
    $m = [regex]::Match($Chunk, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-PortfolioCatalog {
    $path = Get-PortfolioPath
    if (-not $path) { return @() }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $sq = [char]39
    $lb = [char]123
    $marker = "  $lb id:"
    $q = [regex]::Escape([string]$sq)
    $patId = "id:$sq([^$sq]+)$sq"
    $patDemo = "demo:$sq([^$sq]+)$sq"
    $patGh = "gh:$sq([^$sq]+)$sq"
    $patName = "name:" + [regex]::Escape("{") + "he:$sq([^$sq]+)$sq"
    $patStatus = "status:$sq([^$sq]+)$sq"
    $patDesc = "desc:" + [regex]::Escape("{") + "he:$sq([^$sq]+)$sq"
    $items = @()
    $idx = 0
    while (($idx = $content.IndexOf($marker, $idx)) -ge 0) {
        $next = $content.IndexOf($marker, $idx + $marker.Length)
        if ($next -lt 0) { $next = $content.Length }
        $chunk = $content.Substring($idx, $next - $idx)
        $id = Get-PortfolioField $chunk $patId
        if (-not $id) { $idx = $next; continue }
        $demo = Get-PortfolioField $chunk $patDemo
        $gh = Get-PortfolioField $chunk $patGh
        $name = Get-PortfolioField $chunk $patName
        $status = Get-PortfolioField $chunk $patStatus
        if (-not $status) { $status = "unknown" }
        $desc = Get-PortfolioField $chunk $patDesc
        if (-not $demo -and -not $gh) { $idx = $next; continue }
        $items += @{
            id = $id
            name = $name
            demo = $demo
            github = $gh
            status = $status
            desc = $desc
        }
        $idx = $next
    }
    return $items
}

function Normalize-Url([string]$Url) {
    if (-not $Url) { return "" }
    return ($Url.TrimEnd('/') -replace '^https?://', '').ToLower()
}

function Match-PortfolioEntry($Proj, $Catalog) {
    $projDemo = Normalize-Url ([string]$Proj.demo)
    $projGh = Get-GitHubRepoName ([string]$Proj.github)
    $projName = [string]$Proj.name
    foreach ($c in $Catalog) {
        $cDemo = Normalize-Url ([string]$c.demo)
        $cGh = Get-GitHubRepoName ([string]$c.github)
        if ($projDemo -and $cDemo -and $projDemo -eq $cDemo) { return $c }
        if ($projGh -and $cGh -and $projGh -eq $cGh) { return $c }
        if ($c.name -and $projName -and $c.name -eq $projName) { return $c }
    }
    return $null
}

function Format-GitHubUrl([string]$Repo) {
    if (-not $Repo) { return "" }
    if ($Repo -match 'github\.com') { return $Repo.TrimEnd('/') }
    $short = Get-GitHubRepoName $Repo
    if ($short) { return "https://github.com/$short" }
    return $Repo
}

function Get-PortfolioChunks([string]$Content) {
    $sq = [char]39
    $lb = [char]123
    $marker = "  $lb id:"
    $chunks = @{}
    $idx = 0
    while (($idx = $Content.IndexOf($marker, $idx)) -ge 0) {
        $next = $Content.IndexOf($marker, $idx + $marker.Length)
        if ($next -lt 0) { $next = $Content.Length }
        $chunk = $Content.Substring($idx, $next - $idx)
        $q = [regex]::Escape([string]$sq)
        $m = [regex]::Match($chunk, "id:$sq([^$q]+)$sq")
        if ($m.Success) { $chunks[$m.Groups[1].Value] = $chunk }
        $idx = $next
    }
    return $chunks
}

function Set-PortfolioChunkField([string]$Chunk, [string]$FieldName, [string]$NewValue) {
    if (-not $NewValue) { return $Chunk }
    $sq = [char]39
    $q = [regex]::Escape([string]$sq)
    $pat = [regex]::Escape($FieldName) + ":$q[^$q]*$q"
    $replacement = "$FieldName`:$sq$NewValue$sq"
    if ([regex]::IsMatch($Chunk, $pat)) {
        return [regex]::Replace($Chunk, $pat, $replacement, 1)
    }
    return $Chunk
}

function Get-PortfolioDescHe([string]$Chunk) {
    $sq = [char]39
    $q = [regex]::Escape([string]$sq)
    $pat = "desc:\{he:$q([^$q]+)$q"
    $m = [regex]::Match($Chunk, $pat)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Set-PortfolioDescHe([string]$Chunk, [string]$NewDesc) {
    if (-not $NewDesc) { return $Chunk }
    $sq = [char]39
    $q = [regex]::Escape([string]$sq)
    $safe = $NewDesc -replace [string]$sq, "\'"
    $pat = "desc:\{he:$q[^$q]*$q"
    $replacement = "desc:{he:$sq$safe$sq"
    if ([regex]::IsMatch($Chunk, $pat)) {
        return [regex]::Replace($Chunk, $pat, $replacement, 1)
    }
    return $Chunk
}

function Map-BridgeStatusToPortfolio([string]$BridgeStatus, [double]$Progress, [bool]$HasDemo) {
    if ($BridgeStatus -eq "done") { return "live" }
    if ($BridgeStatus -in @("running", "thinking") -and $HasDemo) { return "live" }
    if ($BridgeStatus -in @("running", "thinking", "waiting")) { return "wip" }
    if ($Progress -ge 0.85 -and $HasDemo) { return "live" }
    return "wip"
}

function Get-PortfolioSuggestions($Data, $Catalog, $MatchedIds) {
    $suggestions = @()
    foreach ($c in $Catalog) {
        if ([string]$c.status -ne "live") { continue }
        if (-not $c.demo) { continue }
        if ($MatchedIds[[string]$c.id]) { continue }
        $exists = $false
        foreach ($p in $Data.projects) {
            if (Match-PortfolioEntry $p @($c)) { $exists = $true; break }
        }
        if (-not $exists) {
            $suggestions += @{
                portfolioId = [string]$c.id
                name = [string]$c.name
                demo = [string]$c.demo
                github = (Get-GitHubRepoName ([string]$c.github))
                desc = [string]$c.desc
            }
        }
    }
    return $suggestions
}

function Sync-FromPortfolio {
    $catalog = Get-PortfolioCatalog
    $raw = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json
    $updated = @()
    $matchedIds = @{}

    foreach ($p in $data.projects) {
        $match = Match-PortfolioEntry $p $catalog
        if (-not $match) { continue }
        $matchedIds[[string]$match.id] = $true
        $changed = $false
        $ghRepo = Get-GitHubRepoName ([string]$match.github)
        if ($ghRepo) {
            $curGh = ""
            if ($p.PSObject.Properties.Name -contains "github") { $curGh = [string]$p.github }
            if ($curGh -ne $ghRepo) {
                $p | Add-Member -NotePropertyName github -NotePropertyValue $ghRepo -Force
                $changed = $true
            }
        }
        if ($match.demo) {
            $curDemo = ""
            if ($p.PSObject.Properties.Name -contains "demo") { $curDemo = [string]$p.demo }
            if ((Normalize-Url $curDemo) -ne (Normalize-Url ([string]$match.demo))) {
                $p | Add-Member -NotePropertyName demo -NotePropertyValue ([string]$match.demo) -Force
                $changed = $true
            }
        }
        if ($match.desc) {
            $curGoal = [string]$p.goal
            $portDesc = [string]$match.desc
            if ($portDesc -and $curGoal -ne $portDesc) {
                $p.goal = $portDesc
                $changed = $true
            }
        }
        if ($changed) { $updated += [string]$p.id }
    }

    $suggestions = Get-PortfolioSuggestions $data $catalog $matchedIds
    if ($updated.Count -gt 0) {
        $json = $data | ConvertTo-Json -Depth 25 -Compress:$false
        Save-BridgeData $json
        $script:MetricsCache = $null
    }

    return @{
        ok = $true
        direction = "from"
        catalogCount = $catalog.Count
        portfolioPath = (Get-PortfolioPath)
        pulled = $updated
        updated = $updated
        suggestions = $suggestions
    }
}

function Sync-ToPortfolio {
    $path = Get-PortfolioPath
    if (-not $path) { return @{ ok = $false; error = "portfolio not found" } }

    $catalog = Get-PortfolioCatalog
    $data = Get-BridgeData
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $chunks = Get-PortfolioChunks $content
    $pushed = @()
    $skipped = @()

    foreach ($p in $data.projects) {
        $match = Match-PortfolioEntry $p $catalog
        if (-not $match) { continue }
        $portId = [string]$match.id
        if (-not $chunks.ContainsKey($portId)) { continue }

        $chunk = $chunks[$portId]
        $newChunk = $chunk
        $changed = $false
        $fields = @()

        $bridgeGh = ""
        if ($p.PSObject.Properties.Name -contains "github") { $bridgeGh = [string]$p.github }
        $bridgeDemo = ""
        if ($p.PSObject.Properties.Name -contains "demo") { $bridgeDemo = [string]$p.demo }

        $portGh = Format-GitHubUrl ([string]$match.github)
        $portDemo = [string]$match.demo

        if ($bridgeGh) {
            $targetGh = Format-GitHubUrl $bridgeGh
            if ($targetGh -and (Normalize-Url $portGh) -ne (Normalize-Url $targetGh)) {
                if ([regex]::IsMatch($chunk, "gh:")) {
                    $newChunk = Set-PortfolioChunkField $newChunk "gh" $targetGh
                    $changed = $true
                    $fields += "gh"
                }
            }
        }
        if ($bridgeDemo) {
            if ($portDemo -and (Normalize-Url $portDemo) -ne (Normalize-Url $bridgeDemo)) {
                $newChunk = Set-PortfolioChunkField $newChunk "demo" $bridgeDemo
                $changed = $true
                $fields += "demo"
            } elseif (-not $portDemo -and [regex]::IsMatch($chunk, "demo:")) {
                $newChunk = Set-PortfolioChunkField $newChunk "demo" $bridgeDemo
                $changed = $true
                $fields += "demo"
            }
        }

        $bridgeGoal = [string]$p.goal
        if ($bridgeGoal) {
            $portDescHe = Get-PortfolioDescHe $chunk
            if ($portDescHe -and $portDescHe -ne $bridgeGoal -and [regex]::IsMatch($chunk, "desc:\{he:")) {
                $newChunk = Set-PortfolioDescHe $newChunk $bridgeGoal
                $changed = $true
                $fields += "desc"
            }
        }

        $hasDemo = [bool]$bridgeDemo
        $bridgeStatus = Map-BridgeStatusToPortfolio ([string]$p.status) ([double]$p.progress) $hasDemo
        $portStatus = [string]$match.status
        if ($bridgeStatus -and $portStatus -and $portStatus -ne $bridgeStatus -and [regex]::IsMatch($chunk, "status:")) {
            $newChunk = Set-PortfolioChunkField $newChunk "status" $bridgeStatus
            $changed = $true
            $fields += "status"
        }

        if ($changed) {
            $content = $content.Replace($chunk, $newChunk)
            $chunks[$portId] = $newChunk
            $pushed += @{
                bridgeId = [string]$p.id
                portfolioId = $portId
                name = [string]$p.name
                fields = $fields
            }
        } else {
            $skipped += [string]$p.id
        }
    }

    $backup = $null
    if ($pushed.Count -gt 0) {
        $backup = "$path.bak-bridge-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $path -Destination $backup -Force
        [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    }

    return @{
        ok = $true
        direction = "to"
        portfolioPath = $path
        pushed = $pushed
        pushedCount = $pushed.Count
        skipped = $skipped
        backup = $backup
    }
}

function Get-PortfolioPullPlan($Data, $Catalog) {
    $pull = @()
    foreach ($p in $Data.projects) {
        $match = Match-PortfolioEntry $p $catalog
        if (-not $match) { continue }
        $fields = @()
        $ghRepo = Get-GitHubRepoName ([string]$match.github)
        if ($ghRepo) {
            $curGh = ""
            if ($p.PSObject.Properties.Name -contains "github") { $curGh = [string]$p.github }
            if ($curGh -ne $ghRepo) { $fields += "github" }
        }
        if ($match.demo) {
            $curDemo = ""
            if ($p.PSObject.Properties.Name -contains "demo") { $curDemo = [string]$p.demo }
            if ((Normalize-Url $curDemo) -ne (Normalize-Url ([string]$match.demo))) { $fields += "demo" }
        }
        if ($match.desc) {
            $curGoal = [string]$p.goal
            $portDesc = [string]$match.desc
            if ($portDesc -and $curGoal -ne $portDesc) { $fields += "goal" }
        }
        if ($fields.Count -gt 0) {
            $pull += @{
                bridgeId = [string]$p.id
                portfolioId = [string]$match.id
                name = [string]$p.name
                fields = $fields
            }
        }
    }
    return $pull
}

function Get-PortfolioPushPlan($Data, $Catalog, $Chunks) {
    $push = @()
    foreach ($p in $Data.projects) {
        $match = Match-PortfolioEntry $p $catalog
        if (-not $match) { continue }
        $portId = [string]$match.id
        if (-not $Chunks.ContainsKey($portId)) { continue }
        $chunk = $Chunks[$portId]
        $fields = @()

        $bridgeGh = ""
        if ($p.PSObject.Properties.Name -contains "github") { $bridgeGh = [string]$p.github }
        $bridgeDemo = ""
        if ($p.PSObject.Properties.Name -contains "demo") { $bridgeDemo = [string]$p.demo }
        $portGh = Format-GitHubUrl ([string]$match.github)
        $portDemo = [string]$match.demo

        if ($bridgeGh) {
            $targetGh = Format-GitHubUrl $bridgeGh
            if ($targetGh -and (Normalize-Url $portGh) -ne (Normalize-Url $targetGh) -and [regex]::IsMatch($chunk, "gh:")) {
                $fields += "gh"
            }
        }
        if ($bridgeDemo) {
            if ($portDemo -and (Normalize-Url $portDemo) -ne (Normalize-Url $bridgeDemo)) {
                $fields += "demo"
            } elseif (-not $portDemo -and [regex]::IsMatch($chunk, "demo:")) {
                $fields += "demo"
            }
        }
        $bridgeGoal = [string]$p.goal
        if ($bridgeGoal) {
            $portDescHe = Get-PortfolioDescHe $chunk
            if ($portDescHe -and $portDescHe -ne $bridgeGoal -and [regex]::IsMatch($chunk, "desc:\{he:")) {
                $fields += "desc"
            }
        }
        $hasDemo = [bool]$bridgeDemo
        $bridgeStatus = Map-BridgeStatusToPortfolio ([string]$p.status) ([double]$p.progress) $hasDemo
        $portStatus = [string]$match.status
        if ($bridgeStatus -and $portStatus -and $portStatus -ne $bridgeStatus -and [regex]::IsMatch($chunk, "status:")) {
            $fields += "status"
        }
        if ($fields.Count -gt 0) {
            $push += @{
                bridgeId = [string]$p.id
                portfolioId = $portId
                name = [string]$p.name
                fields = $fields
            }
        }
    }
    return $push
}

function Get-PortfolioSyncPreview([string]$Direction = "both") {
    $dir = ($Direction + "").ToLower().Trim()
    if (-not $dir) { $dir = "both" }
    $path = Get-PortfolioPath
    if (-not $path) {
        return @{ ok = $false; error = "portfolio not found" }
    }
    $catalog = Get-PortfolioCatalog
    $data = Get-BridgeData
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $chunks = Get-PortfolioChunks $content
    $matchedIds = @{}
    foreach ($p in $data.projects) {
        $match = Match-PortfolioEntry $p $catalog
        if ($match) { $matchedIds[[string]$match.id] = $true }
    }
    $result = @{
        ok = $true
        preview = $true
        direction = $dir
        portfolioPath = $path
        catalogCount = $catalog.Count
        pull = @()
        push = @()
        suggestions = @()
    }
    if ($dir -eq "from" -or $dir -eq "both") {
        $result.pull = Get-PortfolioPullPlan $data $catalog
    }
    if ($dir -eq "to" -or $dir -eq "both") {
        $result.push = Get-PortfolioPushPlan $data $catalog $chunks
    }
    $result.suggestions = Get-PortfolioSuggestions $data $catalog $matchedIds
    return $result
}

function Sync-PortfolioBidirectional([string]$Direction = "both") {
    $dir = ($Direction + "").ToLower().Trim()
    if (-not $dir) { $dir = "both" }

    $result = @{
        ok = $true
        direction = $dir
        portfolioPath = (Get-PortfolioPath)
        catalogCount = 0
        pulled = @()
        pushed = @()
        suggestions = @()
        backup = $null
    }

    if ($dir -eq "from" -or $dir -eq "both") {
        $from = Sync-FromPortfolio
        if (-not $from.ok) { return $from }
        $result.catalogCount = $from.catalogCount
        $result.pulled = $from.pulled
        $result.suggestions = $from.suggestions
    }

    if ($dir -eq "to" -or $dir -eq "both") {
        $to = Sync-ToPortfolio
        if (-not $to.ok) {
            $result.ok = $false
            $result.error = $to.error
            return $result
        }
        $result.pushed = $to.pushed
        $result.backup = $to.backup
    }

    if ($dir -eq "both") {
        $result.summary = "pulled=$($result.pulled.Count) pushed=$($result.pushed.Count)"
    }

    return $result
}