#!/bin/bash
set -euo pipefail

# AntGain Desktop installer (Debian/Ubuntu x86_64 .deb)
#   curl -fsSL https://install.antgain.app/install-linux.sh | sudo bash
#   curl -fsSL https://install.antgain.app/install-linux.sh | sudo bash -s 1.0.30

_ag_installer_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$_ag_installer_root" ] && [ -f "${_ag_installer_root}/lib/common.sh" ]; then
  # shellcheck disable=SC1091
  . "${_ag_installer_root}/lib/common.sh"
else
  _ag_common_tmp="$(mktemp)"
  curl -fsSL "${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}/lib/common.sh" -o "$_ag_common_tmp"
  # shellcheck disable=SC1090
  . "$_ag_common_tmp"
  rm -f "$_ag_common_tmp"
fi

ag_log "AntGain Desktop Installer (Linux)"
ag_log "================================"

ag_need_root

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  ag_print_error "This installer supports Desktop on x86_64 only (detected: $ARCH)"
  ag_print_info "For CLI on ARM devices use: ${ANTGAIN_INSTALL_BASE}/install-cli.sh"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  ag_print_error "Only Debian/Ubuntu-based distributions are supported"
  exit 1
fi

TARGET_VERSION="${1:-${VERSION:-}}"
ag_fetch_desktop_deb_url "${TARGET_VERSION:-}" amd64

ag_print_info "Version: ${DESKTOP_VERSION}"
ag_print_info "Package: ${DESKTOP_DEB_URL}"

TMP_DEB="$(mktemp /tmp/antgain_XXXXXX.deb)"
trap 'rm -f "$TMP_DEB"' EXIT

if ! curl -fL# -o "$TMP_DEB" "$DESKTOP_DEB_URL"; then
  ag_print_error "Download failed"
  exit 1
fi

ag_print_info "Updating package index..."
apt-get update -qq 2>/dev/null || true

ag_print_info "Installing package..."
if DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMP_DEB"; then
  ag_print_success "AntGain Desktop installed"
else
  ag_print_error "Installation failed"
  ag_log "Try: sudo apt-get install -f && sudo apt install $TMP_DEB"
  exit 1
fi

ag_log ""
ag_log "How to run:"
ag_log "  Command line: ant-gain"
ag_log "  App menu:     search for AntGain"
ag_log ""
ag_print_success "Installation complete"
