#!/usr/bin/env bash
# Remove Hearthline services. Data stays unless you pass --purge.
# Author: Edson Lourenço
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/firewall.sh
source "$SCRIPT_DIR/lib/firewall.sh"

PURGE=0
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=1
elif [[ -n "${1:-}" ]]; then
  die "Usage: sudo ./uninstall.sh [--purge]"
fi

if [[ $EUID -ne 0 && -f /etc/hearthline/hearthline.env ]]; then
  die "The system install is removed with: sudo $SCRIPT_DIR/uninstall.sh"
fi

ENV_FILE=""
USER_MODE=0
if [[ -f /etc/hearthline/hearthline.env ]]; then
  ENV_FILE=/etc/hearthline/hearthline.env
elif [[ -f "${HOME}/.config/hearthline/hearthline.env" ]]; then
  ENV_FILE="${HOME}/.config/hearthline/hearthline.env"
  USER_MODE=1
else
  die "Hearthline is not installed."
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
CONFIG_DIR=${CONFIG_DIR:-$(dirname "$ENV_FILE")}
RUNTIME_BIN=${RUNTIME_BIN:-$RUNTIME}

stop_unit() {
  local unit=$1
  if [[ "$USER_MODE" -eq 1 ]]; then
    systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
  else
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
  fi
}

log "Stopping Hearthline."
stop_unit hearthline-stackport.service
stop_unit hearthline-ministack.service
"$RUNTIME_BIN" rm -f hearthline-stackport hearthline-ministack >/dev/null 2>&1 || true

if [[ "$USER_MODE" -eq 1 ]]; then
  rm -f "$HOME/.config/systemd/user/hearthline-ministack.service" \
        "$HOME/.config/systemd/user/hearthline-stackport.service" \
        "$HOME/.local/bin/hearthline"
  systemctl --user daemon-reload || true
else
  rm -f /etc/systemd/system/hearthline-ministack.service \
        /etc/systemd/system/hearthline-stackport.service \
        /usr/local/bin/hearthline
  systemctl daemon-reload
fi

if [[ -f "$CONFIG_DIR/firewall.rules" ]]; then
  close_lab_firewall "$CONFIG_DIR/firewall.rules"
fi

if [[ "$PURGE" -eq 1 ]]; then
  log "Removing ${DATA_DIR}."
  rm -rf "$DATA_DIR" "$CONFIG_DIR"
else
  rm -f "$CONFIG_DIR/firewall.rules"
  log "Kept lab data in ${DATA_DIR}."
fi

log "Hearthline services are removed."
