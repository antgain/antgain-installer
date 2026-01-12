#!/bin/bash
set -e

# AntGain CLI Service Installer (Enhanced)
# Usage: 
#   curl -fsSL https://install.antgain.app/cli-service.sh | sudo bash
#   curl -fsSL https://install.antgain.app/cli-service.sh | sudo bash -s YOUR_API_KEY
#   export ANTGAIN_API_KEY=xxx && curl ... | sudo bash

VERSION="1.1.0"

echo "🚀 AntGain CLI Service Installer v${VERSION}"
echo "=============================================="
echo ""

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo "ℹ️  $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Check if antgain is installed
if ! command -v antgain &> /dev/null; then
    print_error "antgain is not installed"
    echo ""
    echo "Install it first:"
    echo "  curl -fsSL https://raw.githubusercontent.com/antgain/antgain-installer/main/install-cli.sh | bash"
    exit 1
fi

ANTGAIN_BIN="$(command -v antgain)"
print_success "Found antgain at: $ANTGAIN_BIN"

# Verify binary is executable
if ! "$ANTGAIN_BIN" --version >/dev/null 2>&1 && ! "$ANTGAIN_BIN" --help >/dev/null 2>&1; then
    print_warning "'$ANTGAIN_BIN' cannot execute --version or --help."
    print_warning "This might indicate an architecture mismatch or missing dependencies."
    print_warning "Continuing, but the service might fail to start."
    echo ""
else
    print_success "Binary verified executable"
fi

# Get API key from: 1. argument, 2. environment variable, 3. interactive input
if [ -n "$1" ]; then
    ANTGAIN_API_KEY="$1"
    print_info "Using API Key from command argument"
elif [ -n "$ANTGAIN_API_KEY" ]; then
    print_info "Using API Key from environment variable"
else
    echo ""
    echo "📝 Please enter your API Key:"
    read -r ANTGAIN_API_KEY
fi

if [ -z "$ANTGAIN_API_KEY" ]; then
    print_error "API Key is required"
    echo ""
    echo "You can provide it in three ways:"
    echo "  1. As argument:     curl ... | sudo bash -s YOUR_API_KEY"
    echo "  2. As environment:  export ANTGAIN_API_KEY=xxx && curl ... | sudo bash"
    echo "  3. Interactive:     curl ... | sudo bash  (will prompt)"
    exit 1
fi

# Validate API key format (basic check)
if [ ${#ANTGAIN_API_KEY} -lt 10 ]; then
    print_warning "API Key seems too short. Please verify it's correct."
fi

echo ""
echo "📦 Configuring service..."
echo ""

# Detect OS
OS="$(uname -s)"
SERVICE_NAME="app.antgain.cli"

# Function to create uninstall script
create_uninstall_script() {
    local os_type="$1"
    local script_path="/usr/local/bin/antgain-uninstall"
    
    if [ "$os_type" = "Darwin" ]; then
        cat > "$script_path" << 'UNINSTALL_EOF'
#!/bin/bash
echo "🗑️  Uninstalling AntGain service..."
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

PLIST_PATH="/Library/LaunchDaemons/app.antgain.cli.plist"

# Stop and unload service
if [ -f "$PLIST_PATH" ]; then
    launchctl unload -w "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "✅ Service removed"
else
    echo "⚠️  Service file not found"
fi

# Clean up logs
rm -f /var/log/antgain.log /var/log/antgain.error.log
echo "✅ Logs cleaned"

# Remove this script
rm -f /usr/local/bin/antgain-uninstall
echo "✅ Uninstall complete!"
UNINSTALL_EOF
    else
        cat > "$script_path" << 'UNINSTALL_EOF'
#!/bin/bash
echo "🗑️  Uninstalling AntGain service..."
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

# Stop and disable service
systemctl stop antgain 2>/dev/null || true
systemctl disable antgain 2>/dev/null || true

# Remove service file
rm -f /etc/systemd/system/antgain.service

# Reload systemd
systemctl daemon-reload

echo "✅ Service removed"

# Remove this script
rm -f /usr/local/bin/antgain-uninstall
echo "✅ Uninstall complete!"
UNINSTALL_EOF
    fi
    
    chmod +x "$script_path"
    print_success "Created uninstall script at $script_path"
}

if [ "$OS" = "Darwin" ]; then
    # ==========================================
    # macOS LaunchDaemon
    # ==========================================
    PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
    
    echo "🍎 Detected macOS"
    print_info "Creating LaunchDaemon at $PLIST_PATH"
    echo ""
    
    # User consent
    echo "⚠️  IMPORTANT NOTICE:"
    echo "   This will install a system service that:"
    echo "   • Starts automatically on system boot"
    echo "   • Restarts automatically if it crashes (not on normal exit)"
    echo "   • Runs with system privileges"
    echo ""
    echo "   You can uninstall anytime by running:"
    echo "   sudo antgain-uninstall"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi
    
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${ANTGAIN_BIN}</string>
    </array>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>ANTGAIN_API_KEY</key>
        <string>${ANTGAIN_API_KEY}</string>
        <key>LOG_LEVEL</key>
        <string>info</string>
    </dict>
    
    <key>RunAtLoad</key>
    <true/>
    
    <!-- Only restart on crash, not on normal exit -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
    <!-- Prevent rapid restart loops -->
    <key>ThrottleInterval</key>
    <integer>60</integer>
    
    <!-- Allow 30 seconds for graceful shutdown -->
    <key>ExitTimeOut</key>
    <integer>30</integer>
    
    <key>StandardOutPath</key>
    <string>/var/log/antgain.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/antgain.error.log</string>
    
    <!-- Prevent running on battery (optional, remove if needed) -->
    <key>StartOnMount</key>
    <false/>
</dict>
</plist>
EOF

    # Set permissions
    chown root:wheel "$PLIST_PATH"
    chmod 644 "$PLIST_PATH"

    # Create log files with proper permissions
    touch /var/log/antgain.log /var/log/antgain.error.log
    chmod 644 /var/log/antgain.log /var/log/antgain.error.log

    # Load service
    echo "🔄 Loading service..."
    # Unload first just in case
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    sleep 1
    launchctl load -w "$PLIST_PATH"
    
    # Wait for service to start
    sleep 2

    print_success "Service installed and started!"
    echo ""
    
    # Verify service is running
    if launchctl list | grep -q "$SERVICE_NAME"; then
        print_success "Service is running"
        launchctl list | grep antgain || true
    else
        print_warning "Service loaded but may not be running yet"
        print_info "Check logs: tail -f /var/log/antgain.error.log"
    fi
    
    # Create uninstall script
    create_uninstall_script "Darwin"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "📚 Useful Commands:"
    echo "═══════════════════════════════════════════════════════════"
    echo "  View logs:"
    echo "    tail -f /var/log/antgain.log"
    echo "    tail -f /var/log/antgain.error.log"
    echo ""
    echo "  Service control:"
    echo "    sudo launchctl stop ${SERVICE_NAME}      # Stop temporarily"
    echo "    sudo launchctl start ${SERVICE_NAME}     # Start"
    echo "    sudo launchctl unload -w $PLIST_PATH     # Disable"
    echo "    sudo launchctl load -w $PLIST_PATH       # Enable"
    echo ""
    echo "  Uninstall:"
    echo "    sudo antgain-uninstall"
    echo "═══════════════════════════════════════════════════════════"

elif [ "$OS" = "Linux" ]; then
    # ==========================================
    # Linux Systemd
    # ==========================================
    echo "🐧 Detected Linux"
    print_info "Creating systemd service"
    echo ""
    
    # User consent
    echo "⚠️  IMPORTANT NOTICE:"
    echo "   This will install a system service that:"
    echo "   • Starts automatically on system boot"
    echo "   • Restarts automatically if it crashes"
    echo "   • Runs as 'nobody' user (limited privileges)"
    echo ""
    echo "   You can uninstall anytime by running:"
    echo "   sudo antgain-uninstall"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled by user"
        exit 0
    fi

    # Create service file
    cat > /etc/systemd/system/antgain.service << EOF
[Unit]
Description=AntGain CLI Node
Documentation=https://docs.antgain.app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup

# Environment
Environment="ANTGAIN_API_KEY=${ANTGAIN_API_KEY}"
Environment="LOG_LEVEL=info"

# Execution
ExecStart=${ANTGAIN_BIN}

# Restart policy: only on failure, not on normal exit
Restart=on-failure
RestartSec=30
StartLimitInterval=300
StartLimitBurst=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/tmp

# Resource limits (optional, adjust as needed)
# LimitNOFILE=65536
# LimitNPROC=512

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=antgain

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    echo "🔄 Reloading systemd..."
    systemctl daemon-reload

    # Enable service
    print_info "Enabling service..."
    systemctl enable antgain

    # Start service
    print_info "Starting service..."
    systemctl start antgain

    # Wait a moment for service to start
    sleep 3

    # Show status
    echo ""
    if systemctl is-active --quiet antgain; then
        print_success "Service is running!"
    else
        print_warning "Service installed but may have failed to start"
        print_info "Check logs: sudo journalctl -u antgain -n 50"
    fi
    
    echo ""
    echo "Service status:"
    systemctl status antgain --no-pager -l || true
    
    # Create uninstall script
    create_uninstall_script "Linux"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "📚 Useful Commands:"
    echo "═══════════════════════════════════════════════════════════"
    echo "  Service control:"
    echo "    sudo systemctl status antgain              # Check status"
    echo "    sudo systemctl stop antgain                # Stop service"
    echo "    sudo systemctl start antgain               # Start service"
    echo "    sudo systemctl restart antgain             # Restart"
    echo "    sudo systemctl disable antgain             # Disable auto-start"
    echo "    sudo systemctl enable antgain              # Enable auto-start"
    echo ""
    echo "  View logs:"
    echo "    sudo journalctl -u antgain -f              # Follow logs"
    echo "    sudo journalctl -u antgain -n 50           # Last 50 lines"
    echo "    sudo journalctl -u antgain --since today   # Today's logs"
    echo ""
    echo "  Uninstall:"
    echo "    sudo antgain-uninstall"
    echo "═══════════════════════════════════════════════════════════"

else
    print_error "Unsupported OS for service installation: $OS"
    echo ""
    echo "Supported platforms:"
    echo "  • macOS (Darwin)"
    echo "  • Linux (systemd)"
    exit 1
fi

echo ""
print_success "Installation complete! 🎉"
echo ""
print_info "The service will start automatically on system boot."
print_info "API Key is stored securely in the service configuration."
echo ""