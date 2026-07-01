param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir

if (-not $OutputPath) {
    $OutputPath = Join-Path $Root "dist\BridgeOS-portable.zip"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$distDir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

$tempRoot = [System.IO.Path]::GetTempPath()
$staging = Join-Path $tempRoot ("BridgeOS-package-" + [Guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $staging "BridgeOS"
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

$excludeDirs = @(".git", "__pycache__", "sessions", "dist")
$excludeFiles = @("bridge-config.json", ".overlay.pid")

try {
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.PSIsContainer -and ($excludeDirs -contains $item.Name)) { continue }
        if (-not $item.PSIsContainer -and ($excludeFiles -contains $item.Name)) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $packageRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }
    Compress-Archive -Path $packageRoot -DestinationPath $OutputPath -CompressionLevel Optimal
    Write-Host "Created package: $OutputPath" -ForegroundColor Green
} finally {
    $fullStaging = [System.IO.Path]::GetFullPath($staging)
    if ($fullStaging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fullStaging)) {
        Remove-Item -LiteralPath $fullStaging -Recurse -Force
    }
}
