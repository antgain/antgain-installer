#!/bin/bash
set -euo pipefail

# AntGain CLI uninstaller
#   curl -fsSL https://install.antgain.app/uninstall-cli.sh | sudo bash
#
# Non-interactive: ANTGAIN_UNINSTALL_YES=1 removes optional Docker/image/config

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

ag_log "AntGain CLI Uninstaller"
ag_log "================================"
ag_log ""

if [ "$EUID" -ne 0 ]; then
  exec sudo -E env \
    ANTGAIN_UNINSTALL_YES="${ANTGAIN_UNINSTALL_YES:-}" \
    ANTGAIN_INSTALLER_DIR="${_ag_installer_root}" \
    bash "$0"
fi

REMOVED=false
AUTO_YES=false
[ "${ANTGAIN_UNINSTALL_YES:-}" = "1" ] && AUTO_YES=true

_ag_ask_yes() {
  local prompt="$1"
  if [ "$AUTO_YES" = true ]; then
    return 0
  fi
  ag_confirm_default_no "$prompt"
}

# systemd / SysV / OpenRC / launchd
if [ "$(uname -s)" = "Linux" ]; then
  if ag_has_systemd && { systemctl list-unit-files antgain.service >/dev/null 2>&1 || [ -f /etc/systemd/system/antgain.service ]; }; then
    ag_print_info "Removing systemd service..."
    ag_remove_systemd_service
    ag_print_success "Removed systemd service"
    REMOVED=true
  fi
  if [ -f /etc/init.d/antgain ] || [ -f "${ANTGAIN_LINUX_ENV_FILE:-/etc/antgain/env}" ]; then
    ag_print_info "Removing SysV/OpenRC/startup helper..."
    ag_remove_linux_fallback_service
    ag_print_success "Removed Linux init/service files"
    REMOVED=true
  fi
elif [ "$(uname -s)" = "Darwin" ]; then
  if [ -f "/Library/LaunchDaemons/${ANTGAIN_SERVICE_NAME}.plist" ]; then
    ag_print_info "Removing LaunchDaemon..."
    ag_remove_launchd_service
    ag_print_success "Removed LaunchDaemon"
    REMOVED=true
  fi
fi

# Legacy helper script
if [ -f /usr/local/bin/antgain-uninstall ]; then
  rm -f /usr/local/bin/antgain-uninstall
fi

# Binary
if [ -f "${ANTGAIN_INSTALL_DIR}/antgain" ] || command -v antgain >/dev/null 2>&1; then
  rm -f "${ANTGAIN_INSTALL_DIR}/antgain" 2>/dev/null || true
  ag_print_success "Removed antgain binary"
  REMOVED=true
fi

# Legacy DEB
if command -v dpkg >/dev/null 2>&1 && dpkg -l antgain-cli >/dev/null 2>&1; then
  ag_print_info "Removing legacy antgain-cli package..."
  apt-get remove -y antgain-cli 2>/dev/null || true
  REMOVED=true
fi

# Docker
if command -v docker >/dev/null 2>&1; then
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx antgain; then
    ag_print_info "Removing Docker container: antgain"
    docker stop antgain 2>/dev/null || true
    docker rm antgain 2>/dev/null || true
    REMOVED=true
  fi

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx watchtower; then
    if _ag_ask_yes "Remove watchtower container? [y/N] "; then
      docker stop watchtower 2>/dev/null || true
      docker rm watchtower 2>/dev/null || true
      ag_print_success "Removed watchtower"
    fi
  fi

  if docker images pinors/antgain-cli -q 2>/dev/null | grep -q .; then
    if _ag_ask_yes "Remove Docker image pinors/antgain-cli? [y/N] "; then
      docker rmi pinors/antgain-cli 2>/dev/null || true
      ag_print_success "Removed Docker image"
    fi
  fi

  if docker volume ls -q 2>/dev/null | grep -qx antgain-data; then
    if _ag_ask_yes "Remove data volume antgain-data (deletes logs)? [y/N] "; then
      docker volume rm antgain-data 2>/dev/null || true
      ag_print_success "Removed volume antgain-data"
    fi
  fi
fi

# Config
if [ -d "${HOME}/.antgain" ]; then
  if _ag_ask_yes "Remove ~/.antgain? [y/N] "; then
    rm -rf "${HOME}/.antgain"
    ag_print_success "Removed ~/.antgain"
  fi
fi

if [ -d "${ANTGAIN_DATA_DIR}" ] && [ "$(uname -s)" = "Linux" ]; then
  if _ag_ask_yes "Remove ${ANTGAIN_DATA_DIR}? [y/N] "; then
    rm -rf "${ANTGAIN_DATA_DIR}"
    ag_print_success "Removed ${ANTGAIN_DATA_DIR}"
  fi
fi

ag_log ""
if [ "$REMOVED" = true ]; then
  ag_print_success "AntGain CLI has been uninstalled"
else
  ag_print_warning "No AntGain CLI installation found"
fi
