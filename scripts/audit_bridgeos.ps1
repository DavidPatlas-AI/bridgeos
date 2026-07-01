param(
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$Desktop = [Environment]::GetFolderPath("Desktop")
$ToolsDir = Join-Path $Desktop "כלים"
$DataFile = Join-Path $Root "bridge-data.json"
$McpConfig = Join-Path $Root "mcp-config.json"

if (-not $ReportPath) {
    $ReportPath = Join-Path $Root "BRIDGE_HEALTH_REPORT.md"
}

function Add-Line([System.Collections.Generic.List[string]]$Lines, [string]$Text = "") {
    $Lines.Add($Text) | Out-Null
}

function Status([bool]$Ok, [string]$Good = "OK", [string]$Bad = "FAIL") {
    if ($Ok) { return $Good }
    return $Bad
}

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines "# BridgeOS Health Report"
Add-Line $lines ""
Add-Line $lines ("Generated: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Add-Line $lines ('Root: "' + $Root + '"')
Add-Line $lines ""

Add-Line $lines "## Server"
try {
    $infoResponse = Invoke-WebRequest -Uri "http://127.0.0.1:8787/api/info" -UseBasicParsing -TimeoutSec 3
    $info = $infoResponse.Content | ConvertFrom-Json
    $sameRoot = [string]$info.root -eq $Root
    Add-Line $lines "- OK: http://127.0.0.1:8787/api/info responded."
    Add-Line $lines ("- " + (Status $sameRoot) + ': server root -> "' + [string]$info.root + '"')
} catch {
    Add-Line $lines ("- FAIL: BridgeOS API is not responding: " + $_.Exception.Message)
}
try {
    $oldServers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.ExecutablePath -like "*powershell.exe" -and $_.CommandLine -like "*Desktop\BridgeOS\bridge.ps1*"
    })
} catch {
    $oldServers = @()
    Add-Line $lines ("- WARN: could not inspect process list: " + $_.Exception.Message)
}
foreach ($old in $oldServers) {
    Add-Line $lines ("- FAIL: old BridgeOS server process still running, PID " + $old.ProcessId)
    Add-Line $lines ('  "' + [string]$old.CommandLine + '"')
}
Add-Line $lines ""

Add-Line $lines "## Projects"
if (Test-Path -LiteralPath $DataFile) {
    $data = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $data.projects) {
        $path = [string]$p.path
        $exists = $path -and (Test-Path -LiteralPath $path)
        $tooBroad = $path -eq $Desktop -or $path -eq (Split-Path -Parent $Desktop)
        $state = if (-not $exists) { "FAIL" } elseif ($tooBroad) { "WARN broad path" } else { "OK" }
        Add-Line $lines ("- " + $state + ": " + $p.id + " " + $p.name + ' -> "' + $path + '"')
    }
} else {
    Add-Line $lines "- FAIL: bridge-data.json missing."
}
Add-Line $lines ""

Add-Line $lines "## Shortcuts and Tools"
$toolChecks = @(
    @{ Name = "Desktop Bridge shortcut"; Path = (Join-Path $Desktop "🌉 Bridge OS.bat") },
    @{ Name = "Tools Bridge shortcut"; Path = (Join-Path $ToolsDir "Bridge OS.bat") },
    @{ Name = "Full desktop"; Path = (Join-Path $ToolsDir "הפעל שולחן עבודה מלא.bat") },
    @{ Name = "Overlay"; Path = (Join-Path $ToolsDir "חוטים שקוף.bat") },
    @{ Name = "Recent files server"; Path = (Join-Path $Desktop "פרויקטים\recent-files-by-project\recent_files_server.py") },
    @{ Name = "Recent files tray"; Path = (Join-Path $Desktop "פרויקטים\recent-files-by-project\recent_files_tray.pyw") },
    @{ Name = "Yomi widget"; Path = (Join-Path $Desktop "פרויקטים\יומי\yomi_widget.pyw") },
    @{ Name = "Status map"; Path = (Join-Path $Desktop "פרויקטים\מפת סטטוס פרויקטים\מפת סטטוס פרויקטים.html") }
)
foreach ($check in $toolChecks) {
    $exists = Test-Path -LiteralPath $check.Path
    Add-Line $lines ("- " + (Status $exists) + ": " + $check.Name + ' -> "' + $check.Path + '"')
}
Add-Line $lines ""

Add-Line $lines "## MCP"
if (Test-Path -LiteralPath $McpConfig) {
    $mcpText = Get-Content -LiteralPath $McpConfig -Raw -Encoding UTF8
    $usesCurrentRoot = $mcpText -like ("*" + $Root.Replace("\", "\\") + "*") -or $mcpText -like ("*" + $Root + "*")
    Add-Line $lines ("- " + (Status $usesCurrentRoot) + ": mcp-config.json points to current BridgeOS root.")
} else {
    Add-Line $lines "- FAIL: mcp-config.json missing."
}
Add-Line $lines ""

Add-Line $lines "## Recommended Fixes"
Add-Line $lines '- Stop any old PowerShell process that serves "Desktop\BridgeOS\bridge.ps1".'
Add-Line $lines '- Keep launchers pointing to "Desktop\פרויקטים\BridgeOS".'
Add-Line $lines "- Replace broad project paths that point only to Desktop with specific project folders."

[System.IO.File]::WriteAllText($ReportPath, ($lines -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
Write-Host "Health report: $ReportPath" -ForegroundColor Green
