#!/bin/bash
set -euo pipefail

# AntGain CLI systemd / launchd service installer
#   curl -fsSL https://install.antgain.app/install-cli-service.sh | sudo bash -s YOUR_API_KEY
#   export ANTGAIN_API_KEY=xxx && curl ... | sudo bash
#
# Env: ANTGAIN_SKIP_CONFIRM=1 (non-interactive), ANTGAIN_INSTALLER_DIR (local dev)

_ag_installer_root="${ANTGAIN_INSTALLER_DIR:-}"
if [ -z "$_ag_installer_root" ]; then
  _ag_installer_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
fi

if [ -n "$_ag_installer_root" ] && [ -f "${_ag_installer_root}/lib/common.sh" ]; then
  # shellcheck disable=SC1091
  . "${_ag_installer_root}/lib/common.sh"
else
  _ag_common_tmp="$(mktemp)"
  if ! curl -fsSL "${ANTGAIN_INSTALL_BASE:-https://install.antgain.app}/lib/common.sh" -o "$_ag_common_tmp"; then
    echo "Failed to load installer library" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$_ag_common_tmp"
  rm -f "$_ag_common_tmp"
fi

ag_log "AntGain CLI Service Installer"
ag_log "================================"

ag_need_root

if ! command -v antgain >/dev/null 2>&1; then
  ag_print_error "antgain is not installed"
  ag_log "Install CLI first:"
  ag_log "  curl -fsSL ${ANTGAIN_INSTALL_BASE}/install-cli.sh | bash"
  exit 1
fi

ag_print_success "Found antgain at: $(command -v antgain)"
ag_verify_cli_binary || ag_print_warning "Binary check failed; continuing anyway"

# API key: arg > env > prompt
if [ -n "${1:-}" ]; then
  ANTGAIN_API_KEY="$1"
elif [ -z "${ANTGAIN_API_KEY:-}" ]; then
  if ag_is_tty; then
    ag_log ""
    read -r -p "Enter your API Key: " ANTGAIN_API_KEY </dev/tty
  else
    ag_print_error "API key required: curl ... | sudo bash -s -- YOUR_API_KEY"
    exit 1
  fi
fi

if [ -z "${ANTGAIN_API_KEY:-}" ]; then
  ag_print_error "API key is required"
  exit 1
fi

if ag_is_version_string "$ANTGAIN_API_KEY"; then
  ag_print_error "Argument looks like a version ($ANTGAIN_API_KEY), not an API key."
  ag_log "Use: curl -fsSL ${ANTGAIN_INSTALL_BASE}/install-cli.sh | bash -s -- VERSION YOUR_API_KEY"
  exit 1
fi
if [ "${#ANTGAIN_API_KEY}" -lt 32 ]; then
  ag_print_warning "API key is shorter than expected (${#ANTGAIN_API_KEY} chars) — please verify"
fi

skip_confirm="false"
if [ "${ANTGAIN_SKIP_CONFIRM:-}" = "1" ] || ! ag_is_tty; then
  skip_confirm="true"
fi

ag_install_and_start_service "$ANTGAIN_API_KEY" "$skip_confirm"
ag_print_service_status

ag_log ""
ag_print_success "Service installation complete"
ag_log "  Linux:   sudo systemctl status antgain"
ag_log "  macOS:   sudo launchctl print system/${ANTGAIN_SERVICE_NAME}"
ag_log "  Uninstall all: curl -fsSL ${ANTGAIN_INSTALL_BASE}/uninstall-cli.sh | sudo bash"
