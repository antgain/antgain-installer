#!/bin/bash
# CLI .deb packages are no longer published. Use the universal tarball installer instead.
set -e

echo "❌ AntGain CLI .deb packages are no longer available." >&2
echo "" >&2
echo "Install with the universal script instead:" >&2
echo "  curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- YOUR_API_KEY" >&2
echo "" >&2
echo "For a systemd service:" >&2
echo "  curl -fsSL https://install.antgain.app/install-cli-service.sh | sudo bash -s -- YOUR_API_KEY" >&2
echo "" >&2
echo "See: https://github.com/proxy-peer/antgain-installer#cli-installation" >&2
exit 1
