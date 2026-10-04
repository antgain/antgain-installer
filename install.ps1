# AntGain CLI Windows Installer
# Usage:
#   irm https://install.antgain.app/install.ps1 | iex
#   $env:VERSION="1.1.4"; $env:ANTGAIN_API_KEY="YOUR_KEY"; irm https://install.antgain.app/install.ps1 | iex
#   $env:ANTGAIN_API_KEY="YOUR_KEY"; irm https://install.antgain.app/install.ps1 | iex

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version = $env:VERSION,
    [Parameter(Position = 1)]
    [string]$ApiKey = $env:ANTGAIN_API_KEY,
    [string]$InstallDir = $env:ANTGAIN_INSTALL_DIR,
    [switch]$SkipStart = $false
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    switch ($Type) {
        "SUCCESS" { Write-Host "✅ $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "❌ $Message" -ForegroundColor Red }
        Default   { Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
    }
}

Write-Host "========================================" -ForegroundColor Blue
Write-Host "      AntGain CLI Windows Installer     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Blue

# 1. Architecture detection
$arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($arch -notmatch '^(AMD64|x86_64)$') {
    throw "Unsupported architecture: $arch. The Windows CLI release supports x64."
}
$platform = "windows-amd64"

Write-Log "Detected Platform: $platform"

# 2. Determine installation directory (Default: %LOCALAPPDATA%\Programs\antgain\bin)
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $InstallDir = Join-Path $localAppData "Programs\antgain\bin"
    } else {
        $InstallDir = Join-Path $env:USERPROFILE ".antgain\bin"
    }
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 3. Resolve version and download URL
$r2Base = if ($env:ANTGAIN_R2_BASE_URL) { $env:ANTGAIN_R2_BASE_URL.TrimEnd('/') } else { "https://cdn.iprobe.io" }
$downloadUrl = ""
$checksumUrl = ""
$targetVersion = ""
$expectedHash = ""

if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $targetVersion = $Version.TrimStart('v').TrimStart('V')
    $archiveName = "antgain-${platform}.tar.gz"
    $downloadUrl = "$r2Base/cli/releases/$targetVersion/$archiveName"
    $checksumUrl = "$downloadUrl.sha256"
} else {
    Write-Log "Resolving latest CLI release from $r2Base/cli/latest.json ..."
    $latestJsonUrl = "$r2Base/cli/latest.json"
    try {
        $manifest = Invoke-RestMethod -TimeoutSec 60 -Uri $latestJsonUrl -UseBasicParsing
    } catch {
        $manifest = Invoke-RestMethod -TimeoutSec 60 -Uri "$r2Base/latest.json" -UseBasicParsing
    }

    if ($manifest.downloads -and $manifest.downloads.cli -and $manifest.downloads.cli.files) {
        $fileEntry = $manifest.downloads.cli.files.$platform
        if ($fileEntry -and $fileEntry.url) {
            $downloadUrl = $fileEntry.url
            $checksumUrl = "$downloadUrl.sha256"
            $expectedHash = $fileEntry.sha256
        }
        $targetVersion = $manifest.downloads.cli.version
    }

    if ([string]::IsNullOrWhiteSpace($targetVersion) -and $manifest.version) {
        $targetVersion = $manifest.version
    }
    $targetVersion = $targetVersion -replace '^[vV]', ''

    if ([string]::IsNullOrWhiteSpace($downloadUrl) -and -not [string]::IsNullOrWhiteSpace($targetVersion)) {
        $downloadUrl = "$r2Base/cli/releases/$targetVersion/antgain-${platform}.tar.gz"
        $checksumUrl = "$downloadUrl.sha256"
    }
}

if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
    Write-Log "Failed to resolve download URL for platform $platform" "ERROR"
    exit 1
}

Write-Log "Target Version: $targetVersion"
Write-Log "Download URL: $downloadUrl"

# 4. Download archive to temp directory and verify SHA-256
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("antgain_install_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$archivePath = Join-Path $tempDir "antgain.tar.gz"

try {
    Write-Log "Downloading package..."
    Invoke-WebRequest -TimeoutSec 600 -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        try {
            $checksumResponse = Invoke-WebRequest -TimeoutSec 60 -Uri $checksumUrl -UseBasicParsing
            $checksumContent = if ($checksumResponse.Content -is [byte[]]) {
                [System.Text.Encoding]::UTF8.GetString($checksumResponse.Content)
            } else { [string]$checksumResponse.Content }
            $checksumContent = $checksumContent.Trim()
            $expectedHash = ($checksumContent -split '\s+')[0].ToLowerInvariant()
        } catch {
            throw "Cannot download SHA-256 checksum; installed version preserved."
        }
    }
    if ($expectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw "Missing or invalid SHA-256 checksum" }
    $expectedHash = $expectedHash.ToLowerInvariant()
    if ($expectedHash) {
        $actualHash = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            Write-Log "SHA256 verification failed! Expected: $expectedHash, Got: $actualHash" "ERROR"
            exit 1
        }
        Write-Log "SHA256 verified successfully ($actualHash)" "SUCCESS"
    }

    # 5. Extract archive
    Write-Log "Extracting package..."
    tar -xzf $archivePath -C $tempDir
    if ($LASTEXITCODE -ne 0) { throw "Package extraction failed" }

    # Find extracted antgain.exe
    $extractedExe = Get-ChildItem -Path $tempDir -Filter "antgain.exe" -Recurse | Select-Object -First 1
    if (-not $extractedExe) {
        Write-Log "Could not find antgain.exe in extracted archive!" "ERROR"
        exit 1
    }

    # Verify the candidate before stopping or replacing an existing node.
    $versionOutput = & $extractedExe.FullName --version
    if ($LASTEXITCODE -ne 0) { throw "Downloaded executable cannot run on this system" }
    $targetExePath = Join-Path $InstallDir "antgain.exe"
    $backupExePath = Join-Path $InstallDir ("antgain.install-backup-" + [Guid]::NewGuid().ToString("N") + ".exe")
    $wasRunning = $false
    $runningProcesses = Get-Process -Name "antgain" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $targetExePath }
    if ($runningProcesses) {
        $wasRunning = $true
        & $targetExePath stop
        Start-Sleep -Seconds 2
        Get-Process -Name antgain -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $targetExePath } |
            Stop-Process -Force -ErrorAction Stop
    }
    $hadPrevious = Test-Path $targetExePath
    try {
        if ($hadPrevious) { Move-Item $targetExePath $backupExePath -ErrorAction Stop }
        Copy-Item $extractedExe.FullName $targetExePath -ErrorAction Stop
        & $targetExePath --version
        if ($LASTEXITCODE -ne 0) { throw "Installed executable verification failed" }
    } catch {
        if (Test-Path $backupExePath) {
            Remove-Item $targetExePath -Force -ErrorAction SilentlyContinue
            Move-Item $backupExePath $targetExePath -ErrorAction Stop
        } elseif (-not $hadPrevious) {
            Remove-Item $targetExePath -Force -ErrorAction SilentlyContinue
        }
        if ($wasRunning -and (Test-Path $targetExePath)) { & $targetExePath run --daemon }
        throw
    }
    if (Test-Path $backupExePath) { Remove-Item $backupExePath -Force }
    Write-Log "Installed: $versionOutput" "SUCCESS"

} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Remember the executable location without reading or changing client configuration.
$installerRegistry = 'HKCU:\Software\AntGain\CLI'
New-Item -Path $installerRegistry -Force | Out-Null
Set-ItemProperty -Path $installerRegistry -Name InstallDir -Value $InstallDir

# 7. Configure user environment variable PATH
$userPath = [string][Environment]::GetEnvironmentVariable("Path", "User")
$pathList = ($userPath -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
if ($pathList -notcontains $InstallDir) {
    Write-Log "Adding $InstallDir to user PATH environment variable..."
    $newUserPath = "$InstallDir;" + $userPath.TrimEnd(';')
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    Write-Log "User PATH updated successfully." "SUCCESS"
} else {
    Write-Log "Install directory is already in user PATH."
}

# Refresh this process too; a previously opened terminal may have a stale PATH.
if (($env:Path -split ';') -notcontains $InstallDir) { $env:Path = "$InstallDir;$env:Path" }

# Let the executable own configuration encryption and identity preservation.
$previousApiKey = $env:ANTGAIN_API_KEY
try {
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $env:ANTGAIN_API_KEY = $ApiKey
        $helpText = (& $targetExePath --help | Out-String)
        if ($helpText -match '(?m)^\s+configure\s') {
            & $targetExePath configure
            if ($LASTEXITCODE -ne 0) { throw "Could not save credentials; existing configuration was preserved" }
        } else {
            Write-Log "Credentials will be saved by the client on first start."
        }
    }
    $skipByEnv = $env:ANTGAIN_SKIP_START -match '^(1|true|yes|on)$' -or $env:ANTGAIN_AUTO_START -match '^(0|false|no|off)$'
    if (-not $SkipStart -and -not $skipByEnv -and (-not [string]::IsNullOrWhiteSpace($ApiKey) -or $wasRunning)) {
        & $targetExePath run --daemon
        if ($LASTEXITCODE -ne 0) { throw "Installed executable could not start; run antgain check for details" }
        Write-Log "Node started in background." "SUCCESS"
    }
} finally {
    $env:ANTGAIN_API_KEY = $previousApiKey
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "   AntGain CLI Installed Successfully!  " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Host "  1. Configure your API key:" -ForegroundColor Yellow
    Write-Host '     $env:ANTGAIN_API_KEY="YOUR_API_KEY"; antgain run --daemon' -ForegroundColor White
} else {
    Write-Host "  1. Run diagnostics & health check:" -ForegroundColor Yellow
    Write-Host "     antgain check" -ForegroundColor White
    Write-Host "  2. Start the AntGain node (background):" -ForegroundColor Yellow
    Write-Host "     antgain start -d" -ForegroundColor White
}
Write-Host "  3. Check status and earnings anytime:" -ForegroundColor Yellow
Write-Host "     antgain status" -ForegroundColor White
Write-Host "  4. View real-time logs:" -ForegroundColor Yellow
Write-Host "     antgain logs -f" -ForegroundColor White
Write-Host "  5. Update to latest version:" -ForegroundColor Yellow
Write-Host "     antgain update" -ForegroundColor White
Write-Host "  6. Uninstall:" -ForegroundColor Yellow
Write-Host "     irm https://install.antgain.app/uninstall.ps1 | iex" -ForegroundColor White
Write-Host ""
Write-Host "Need an API key? Get it at: https://antgain.app/dashboard/settings" -ForegroundColor Gray
