# AntGain CLI Windows Uninstaller
# Usage:
#   irm https://install.antgain.app/uninstall.ps1 | iex
#   $env:ANTGAIN_UNINSTALL_PURGE="1"; irm https://install.antgain.app/uninstall.ps1 | iex

[CmdletBinding()]
param(
    [switch]$Purge = ($env:ANTGAIN_UNINSTALL_PURGE -match "^(1|true|yes|on)$"),
    [switch]$Force = $false
)

$ErrorActionPreference = "Stop"

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
Write-Host "     AntGain CLI Windows Uninstaller    " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Blue

# Restrict removal and stopping to this user's installed CLI paths.
$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$possibleDirs = @(
    (Join-Path $localAppData "Programs\antgain\bin"),
    (Join-Path $env:USERPROFILE ".antgain\bin")
)
if ($env:ANTGAIN_INSTALL_DIR) { $possibleDirs += $env:ANTGAIN_INSTALL_DIR }
$installerRegistry = 'HKCU:\Software\AntGain\CLI'
$storedInstall = Get-ItemProperty -Path $installerRegistry -Name InstallDir -ErrorAction SilentlyContinue
if ($storedInstall -and $storedInstall.InstallDir) { $possibleDirs += $storedInstall.InstallDir }
$possibleDirs = $possibleDirs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { [System.IO.Path]::GetFullPath($_) } | Select-Object -Unique
foreach ($dir in $possibleDirs) {
    $exePath = Join-Path $dir "antgain.exe"
    if (Test-Path $exePath) { & $exePath stop }
    Get-Process -Name antgain -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exePath } |
        Stop-Process -Force -ErrorAction Stop
}
# Desktop may use the same startup name. Only remove a CLI startup command.
$startupRegistry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupValue = (Get-ItemProperty -Path $startupRegistry -Name AntGain -ErrorAction SilentlyContinue).AntGain
if ($startupValue) {
    $startupCommand = [Environment]::ExpandEnvironmentVariables([string]$startupValue)
    foreach ($dir in $possibleDirs) {
        $cliExe = Join-Path $dir 'antgain.exe'
        if ($startupCommand -match ('^\s*"?' + [regex]::Escape($cliExe) + '"?(?:\s|$)')) {
            Remove-ItemProperty -Path $startupRegistry -Name AntGain -ErrorAction Stop
            break
        }
    }
}

$removedBin = $false
foreach ($dir in $possibleDirs) {
    $exePath = Join-Path $dir "antgain.exe"
    $oldPath = Join-Path $dir "antgain.old.exe"
    $stablePath = Join-Path $dir "antgain.stable.exe"

    if (Test-Path $exePath) {
        Remove-Item -Path $exePath -Force -ErrorAction Stop
        $removedBin = $true
        Write-Log "Removed $exePath" "SUCCESS"
    }
    if (Test-Path $oldPath) {
        Remove-Item -Path $oldPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $stablePath) {
        Remove-Item -Path $stablePath -Force -ErrorAction SilentlyContinue
    }

    # Remove from user PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -and $userPath.Contains($dir)) {
        $pathItems = ($userPath -split ';') | Where-Object { $_ -ne $dir -and -not [string]::IsNullOrWhiteSpace($_) }
        $newUserPath = $pathItems -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Log "Removed $dir from user PATH." "SUCCESS"
    }
}

Remove-Item -Path $installerRegistry -Recurse -Force -ErrorAction SilentlyContinue
$env:Path = (($env:Path -split ';') | Where-Object { $_ -notin $possibleDirs }) -join ';'

# 3. Prompt or purge data/config directory
$cfgDir = Join-Path $env:USERPROFILE ".antgain"
$shouldPurge = $Purge

if (-not $shouldPurge -and -not $Force -and (Test-Path $cfgDir)) {
    $choice = Read-Host "Do you want to purge configuration, credentials, and logs ($cfgDir)? [y/N]"
    if ($choice -match '^(y|yes)$') {
        $shouldPurge = $true
    }
}

if ($shouldPurge -and (Test-Path $cfgDir)) {
    try {
        Remove-Item -Path $cfgDir -Recurse -Force -ErrorAction Stop
        Write-Log "Purged data directory: $cfgDir" "SUCCESS"
    } catch {
        Write-Log "Could not fully remove $cfgDir : $_" "WARN"
    }
} elseif (Test-Path $cfgDir) {
    Write-Log "Data directory preserved at $cfgDir" "INFO"
}

Write-Host ""
Write-Log "AntGain CLI has been successfully uninstalled from this system." "SUCCESS"
