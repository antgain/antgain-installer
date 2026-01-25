#!/bin/bash
set -e

# AntGain CLI DEB Installation Script
# CLI command line tool installation for Debian/Ubuntu systems (via deb package)
# Usage: 
#   curl -fsSL https://install.antgain.app/install-cli-deb.sh | sudo bash
#   curl -fsSL https://install.antgain.app/install-cli-deb.sh | sudo bash -s 1.0.26

echo "🚀 AntGain CLI DEB Installer"
echo "================================"

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run with root privileges (use sudo)"
    exit 1
fi

# Configuration
R2_BASE_URL="${R2_BASE_URL:-https://pub-a6321dc4515447b698de8db2567150ff.r2.dev}"

# Get Version: 1. Command argument, 2. Environment variable, 3. Auto-fetch latest version
if [ -n "$1" ]; then
    VERSION="$1"
elif [ -z "$VERSION" ]; then
    VERSION=""
fi

# Detect system architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        ARCH_TYPE="amd64"
        ;;
    aarch64|arm64)
        ARCH_TYPE="arm64"
        ;;
    *)
        echo "❌ Error: Unsupported architecture $ARCH (only x86_64/amd64 and arm64 are supported)"
        exit 1
        ;;
esac

echo "📋 System Info:"
echo "  Architecture: $ARCH_TYPE"

# Detect distribution
if ! command -v apt-get &> /dev/null; then
    echo "❌ Error: Only Debian/Ubuntu apt-based systems are supported"
    echo ""
    echo "If you are using another Linux distribution, please use the universal installation script:"
    echo "  curl -fsSL https://install.antgain.app/install-cli.sh | bash"
    exit 1
fi

# Get Version
if [ -n "$VERSION" ]; then
    echo "📦 Using specified version: v$VERSION"
else
    # Fetch latest version from R2
    echo "📡 Fetching latest CLI version..."
    LATEST_JSON="${R2_BASE_URL}/cli/latest.json"
    
    VERSION_DATA=$(curl -fsSL "$LATEST_JSON" 2>/dev/null || echo "")
    
    if [ -z "$VERSION_DATA" ]; then
        echo "❌ Unable to fetch latest version information"
        echo ""
        echo "You can manually specify a version to bypass the version check:"
        echo "  curl -fsSL ... | sudo bash -s 1.0.26"
        echo ""
        echo "Or check your network connection and try again."
        exit 1
    fi
    
    # Extract version
    VERSION=$(echo "$VERSION_DATA" | grep -o '"version":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -z "$VERSION" ]; then
        echo "❌ Error: Unable to parse version information"
        exit 1
    fi
    
    echo "📦 Latest version: v$VERSION"
fi

# Build download URL
DEB_FILENAME="antgain-cli_${VERSION}-1_${ARCH_TYPE}.deb"
DEB_URL="${R2_BASE_URL}/cli/releases/${VERSION}/${DEB_FILENAME}"

echo "📥 Download URL: $DEB_URL"

# Download
echo "📥 Downloading..."
TMP_DEB="/tmp/antgain-cli_${VERSION}_${ARCH_TYPE}.deb"
if ! curl -fL -o "$TMP_DEB" "$DEB_URL"; then
    echo "❌ Download failed"
    echo ""
    echo "Please check if the version is correct, or try the universal installation script:"
    echo "  curl -fsSL https://install.antgain.app/install-cli.sh | bash"
    exit 1
fi

# Update package list
echo "🔄 Updating package list..."
apt-get update -qq 2>/dev/null || true

# Install
echo "📦 Installing AntGain CLI..."
if apt-get install -y "$TMP_DEB"; then
    echo "✅ Installation successful!"
    echo ""
    echo "Usage:"
    echo "  antgain --api-key YOUR_API_KEY"
    echo ""
    echo "View Help:"
    echo "  antgain --help"
else
    echo "❌ Installation failed"
    echo ""
    echo "Manually fix dependencies:"
    echo "  sudo apt install -f"
    rm -f "$TMP_DEB"
    exit 1
fi

# Cleanup
rm -f "$TMP_DEB"

echo ""
echo "🎉 Installation complete!"
echo ""
echo "Get API Key: https://antgain.app/dashboard/settings"
echo ""
echo "Run as system service:"
echo "  curl -fsSL https://install.antgain.app/install-cli-service.sh | sudo bash"
