#!/bin/bash
set -e

# AntGain CLI Installation Script
# Usage: 
#   curl -fsSL https://install.antgain.app/cli.sh | bash
#   curl -fsSL https://install.antgain.app/cli.sh | bash -s 1.0.0
#   curl -fsSL https://install.antgain.app/cli.sh | bash -s YOUR_API_KEY

echo "🚀 AntGain CLI Installer"
echo "================================"

# Configuration
R2_BASE_URL="${R2_BASE_URL:-https://pub-a6321dc4515447b698de8db2567150ff.r2.dev}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Detect OS and Architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        OS_TYPE="linux"
        ;;
    Darwin*)
        OS_TYPE="darwin"
        ;;
    *)
        echo "❌ Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        ARCH_TYPE="amd64"
        ;;
    aarch64|arm64)
        ARCH_TYPE="arm64"
        ;;
    *)
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

PLATFORM_KEY="${OS_TYPE}-${ARCH_TYPE}"

echo "📋 System Info:"
echo "  OS: $OS_TYPE"
echo "  Arch: $ARCH_TYPE"
echo "  Key: $PLATFORM_KEY"

# Get version or API key from argument
API_KEY=""
VERSION=""

if [ -n "$1" ]; then
    # Simple regex to check if it looks like a version number (v1.0.0 or 1.0.0)
    if [[ "$1" =~ ^[vV]?[0-9]+\.[0-9]+\.[0-9]+.*$ ]]; then
        VERSION="$1"
    else
        API_KEY="$1"
    fi
fi

if [ -n "$VERSION" ]; then
    echo "🎯 Target Version: $VERSION"
elif [ -z "$VERSION" ]; then
    # Fetch latest version
    echo "📡 Fetching latest CLI version..."
    LATEST_JSON_URL="${R2_BASE_URL}/cli/latest.json"

    VERSION_DATA=$(curl -fsSL "$LATEST_JSON_URL" 2>/dev/null || echo "")
    
    if [ -z "$VERSION_DATA" ]; then
        echo "❌ Failed to fetch version info"
        echo ""
        echo "You can install manually from:"
        echo "  https://github.com/proxy-peer/antgain/releases"
        exit 1
    fi
    
    # Extract URL for the specific platform
    # Strategy: Flatten JSON to single line, find "linux-amd64": { ... } and extract "url" value from it.
    # We grep for: "KEY": *{ [any chars not }] }
    DOWNLOAD_URL=$(echo "$VERSION_DATA" | tr -d '\n' | grep -o "\"$PLATFORM_KEY\":[[:space:]]*{[^}]*}" | grep -o '"url":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

    # Fallback extraction: extract the first version number found
    VERSION=$(echo "$VERSION_DATA" | tr -d '\n' | grep -o '"version":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "❌ Could not find a download URL for platform: $PLATFORM_KEY"
        echo "Available keys might be different currently."
        exit 1
    fi
fi

echo "📦 Found version: $VERSION"

if [ -z "$DOWNLOAD_URL" ]; then
    # If version specified manually, construct URL
    FILENAME="antgain-${OS_TYPE}-${ARCH_TYPE}.tar.gz"
    DOWNLOAD_URL="${R2_BASE_URL}/cli/releases/${VERSION}/${FILENAME}"
fi

echo "📥 Downloading from: $DOWNLOAD_URL"

# Download
TMP_DIR=$(mktemp -d)
FILENAME="antgain.tar.gz"
cd "$TMP_DIR"

if ! curl -fL -o "$FILENAME" "$DOWNLOAD_URL"; then
    echo "❌ Download failed"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract
echo "📦 Extracting..."
tar xzf "$FILENAME"

# Install
# Determine the binary name. It usually extracts to 'antgain' or a folder.
# We'll assume it extracts 'antgain' binary in the current dir or immediate subdir.
if [ -f "antgain" ]; then
    BINARY="antgain"
elif [ -f "antgain-${PLATFORM_KEY}/antgain" ]; then
    BINARY="antgain-${PLATFORM_KEY}/antgain"
else
    # Try to find it
    BINARY=$(find . -type f -name "antgain" | head -n 1)
fi

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
    echo "❌ Could not find 'antgain' binary in extracted archive."
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "📦 Installing to $INSTALL_DIR..."
if [ -w "$INSTALL_DIR" ]; then
    mv "$BINARY" "$INSTALL_DIR/antgain"
    chmod +x "$INSTALL_DIR/antgain"
else
    sudo mv "$BINARY" "$INSTALL_DIR/antgain"
    sudo chmod +x "$INSTALL_DIR/antgain"
fi

# Cleanup
cd - > /dev/null
rm -rf "$TMP_DIR"

echo "✅ Installation successful!"
echo ""

if [ -n "$API_KEY" ]; then
    echo "🔑 API Key detected. Setting up systemd service..."
    # URL for service installer
    SERVICE_INSTALLER_URL="https://raw.githubusercontent.com/antgain/antgain-installer/main/install-cli-service.sh"
    
    echo "📥 Fetching service installer..."
    if [ "$EUID" -ne 0 ]; then
        curl -fsSL "$SERVICE_INSTALLER_URL" | sudo bash -s "$API_KEY"
    else
        curl -fsSL "$SERVICE_INSTALLER_URL" | bash -s "$API_KEY"
    fi
else
    echo "Usage:"
    echo "  antgain --api-key YOUR_API_KEY"
    echo ""
    echo "Get your API key from: https://antgain.app/dashboard/settings"
    echo ""
    echo "Run as systemd service:"
    echo "  curl -fsSL https://raw.githubusercontent.com/antgain/antgain-installer/main/install-cli-service.sh | sudo bash -s YOUR_API_KEY"
fi
