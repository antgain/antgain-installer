#!/bin/bash
set -euo pipefail

# AntGain CLI installer
#   curl -fsSL https://install.antgain.app/install-cli.sh | bash
#   curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- 1.1.0
#   curl -fsSL https://install.antgain.app/install-cli.sh | bash -s -- YOUR_API_KEY
#   VERSION=1.1.0 curl -fsSL https://install.antgain.app/install-cli.sh | bash
# See README.md: command syntax, version pinning, macOS quarantine, publishing releases.
#
# Env: VERSION, ANTGAIN_API_KEY, ANTGAIN_AUTO_START=true, ANTGAIN_SKIP_START=1

_ag_installer_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$_ag_installer_root" ] && [ -f "${_ag_installer_root}/lib/common.sh" ]; then
  ANTGAIN_INSTALLER_DIR="$_ag_installer_root"
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

ag_log "AntGain CLI Installer"
ag_log "================================"

ag_detect_platform
ag_parse_cli_args "$@"
ag_validate_cli_install_args || exit 1

ag_log "System: ${OS_TYPE}/${ARCH_TYPE} (${PLATFORM_KEY})"
[ -n "${TARGET_VERSION:-}" ] && ag_log "Target version: ${TARGET_VERSION}"
[ -n "${ANTGAIN_API_KEY:-}" ] && ag_log "API key: provided (${#ANTGAIN_API_KEY} chars)"

ag_install_cli_binary "$PLATFORM_KEY" "${TARGET_VERSION:-}" "$ANTGAIN_INSTALL_DIR"

_verify_ok=true
if ! ag_verify_cli_binary; then
  _verify_ok=false
  ag_print_warning "Binary verification failed (see above); will still try service setup if API key was provided"
fi

if [ "$_verify_ok" = true ]; then
  ag_log ""
  ag_print_success "AntGain CLI installed successfully"
fi

_run_service_install() {
  export ANTGAIN_SKIP_CONFIRM=1
  if [ -n "$_ag_installer_root" ] && [ -f "${_ag_installer_root}/install-cli-service.sh" ]; then
    if [ "$EUID" -eq 0 ]; then
      bash "${_ag_installer_root}/install-cli-service.sh" "$ANTGAIN_API_KEY"
    else
      sudo env ANTGAIN_INSTALLER_DIR="$_ag_installer_root" ANTGAIN_SKIP_CONFIRM=1 \
        bash "${_ag_installer_root}/install-cli-service.sh" "$ANTGAIN_API_KEY"
    fi
  else
    if [ "$EUID" -eq 0 ]; then
      curl -fsSL "${ANTGAIN_INSTALL_BASE}/install-cli-service.sh" | bash -s -- "$ANTGAIN_API_KEY"
    else
      curl -fsSL "${ANTGAIN_INSTALL_BASE}/install-cli-service.sh" | sudo env ANTGAIN_SKIP_CONFIRM=1 bash -s -- "$ANTGAIN_API_KEY"
    fi
  fi
}

if [ -n "${ANTGAIN_API_KEY:-}" ] && ag_should_install_service; then
  ag_log ""
  if ag_should_start_service; then
    ag_print_info "API key provided — installing and starting background service..."
  else
    ag_print_info "API key provided — installing background service (ANTGAIN_AUTO_START=false, will not start)..."
  fi
  if ! _run_service_install; then
    ag_print_warning "Background service setup did not complete; CLI binary is installed."
    ag_print_linux_manual_start_hints
  else
    ag_print_service_status
  fi
elif [ -n "${ANTGAIN_API_KEY:-}" ] && ! ag_should_install_service; then
  ag_print_info "Skipped service install (ANTGAIN_SKIP_START). Run: curl -fsSL ${ANTGAIN_INSTALL_BASE}/install-cli-service.sh | sudo bash -s -- YOUR_API_KEY"
else
  ag_log ""
  ag_log "Next steps:"
  ag_log "  1. Run:  export ANTGAIN_API_KEY=your-key && antgain"
  ag_log "  2. Service: curl -fsSL ${ANTGAIN_INSTALL_BASE}/install-cli-service.sh | sudo bash -s -- YOUR_API_KEY"
  ag_log "  3. Uninstall: curl -fsSL ${ANTGAIN_INSTALL_BASE}/uninstall-cli.sh | sudo bash"
  ag_log ""
  ag_log "Get your API key: https://antgain.app/dashboard/settings"
fi

if [ "$_verify_ok" != true ]; then
  exit 1
fi
