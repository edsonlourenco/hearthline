#!/usr/bin/env bash
# Hearthline — deploy MiniStack and StackPort, and start them on boot.
# Author: Edson Lourenço
# https://github.com/edsonlourenco/hearthline
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck source=lib/firewall.sh
source "$SCRIPT_DIR/lib/firewall.sh"
# shellcheck source=lib/aws.sh
source "$SCRIPT_DIR/lib/aws.sh"
# shellcheck source=lib/systemd.sh
source "$SCRIPT_DIR/lib/systemd.sh"

RUNTIME=""
LAN_IP=""
SUBNET=""
IFACE=""
PREFIX=""
REGION="us-east-1"
MINISTACK_PORT=4566
STACKPORT_PORT=8080
WITH_STACKPORT=1
WITH_AWSCLI=1
WITH_FIREWALL=1
REAL_INFRA=0
USER_MODE=0
PRINT_PLAN=0
AWS_KEY="test"
AWS_SECRET="test"
MINISTACK_IMAGE="docker.io/ministackorg/ministack:full"
STACKPORT_IMAGE="docker.io/davireis/stackport:latest"
RUNTIME_NEEDS_INSTALL=0

usage() {
  cat <<EOF
Hearthline installs a local AWS lab and starts it when the machine boots.

Usage:
  sudo ./install.sh [options]

Options:
  --runtime podman|docker   Engine to use. Default: Podman if it exists, otherwise Docker.
  --user                    Rootless install. Boot then depends on systemd linger.
  --lan-ip ADDRESS          Address other computers use. Default: this host's LAN address.
  --subnet CIDR             Firewall scope. Default: the LAN prefix, often a /24.
  --iface NAME              Interface used to detect the LAN. Default: the default route.
  --prefix DIR              Data directory. Default: /var/lib/hearthline
  --region NAME             MiniStack region. Default: us-east-1
  --ministack-port PORT     Host port for the AWS API. Default: 4566
  --stackport-port PORT     Host port for the web console. Default: 8080
  --real-infra              Mount the engine socket so MiniStack can start sidecar containers.
  --skip-stackport          Install MiniStack only.
  --skip-awscli             Do not install or configure the AWS CLI.
  --skip-firewall           Do not change firewalld or UFW.
  --print-plan              Show the decisions and exit without changing the host.
  -h, --help                Show this help.

The installer is idempotent. Run it again after an address or image change.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --runtime)
        [[ $# -ge 2 ]] || die "--runtime needs a value"
        RUNTIME=$2
        shift 2
        ;;
      --lan-ip)
        [[ $# -ge 2 ]] || die "--lan-ip needs a value"
        LAN_IP=$2
        shift 2
        ;;
      --subnet)
        [[ $# -ge 2 ]] || die "--subnet needs a value"
        SUBNET=$2
        shift 2
        ;;
      --iface)
        [[ $# -ge 2 ]] || die "--iface needs a value"
        IFACE=$2
        shift 2
        ;;
      --prefix)
        [[ $# -ge 2 ]] || die "--prefix needs a value"
        PREFIX=$2
        shift 2
        ;;
      --region)
        [[ $# -ge 2 ]] || die "--region needs a value"
        REGION=$2
        shift 2
        ;;
      --ministack-port)
        [[ $# -ge 2 ]] || die "--ministack-port needs a value"
        MINISTACK_PORT=$2
        shift 2
        ;;
      --stackport-port)
        [[ $# -ge 2 ]] || die "--stackport-port needs a value"
        STACKPORT_PORT=$2
        shift 2
        ;;
      --real-infra) REAL_INFRA=1; shift ;;
      --user) USER_MODE=1; shift ;;
      --skip-stackport) WITH_STACKPORT=0; shift ;;
      --skip-awscli) WITH_AWSCLI=0; shift ;;
      --skip-firewall) WITH_FIREWALL=0; shift ;;
      --print-plan) PRINT_PLAN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1. Try --help." ;;
    esac
  done
}

print_plan() {
  local mode firewall aws infra stackport runtime_note="" image_note=""
  if [[ "$USER_MODE" -eq 1 ]]; then
    mode="rootless user service (boot needs linger)"
  else
    mode="system service, starts at boot"
  fi
  if [[ "$RUNTIME_NEEDS_INSTALL" -eq 1 ]]; then
    runtime_note=" (will install)"
  fi
  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    stackport="http://${LAN_IP}:${STACKPORT_PORT}"
    image_note=$'\n'"               ${STACKPORT_IMAGE}"
  else
    stackport="skipped"
  fi
  if [[ "$WITH_FIREWALL" -eq 1 ]]; then
    firewall=$(firewall_backend)
  else
    firewall=skipped
  fi
  if [[ "$WITH_AWSCLI" -eq 1 ]]; then
    aws="profile hearthline"
  else
    aws=skipped
  fi
  if [[ "$REAL_INFRA" -eq 1 ]]; then
    infra="engine socket mounted"
  else
    infra=off
  fi
  cat <<EOF
Hearthline plan
  host:        ${OS_PRETTY}
  family:      ${OS_FAMILY}
  runtime:     ${RUNTIME}${runtime_note}
  mode:        ${mode}
  interface:   ${IFACE}
  lan address: ${LAN_IP}
  subnet:      ${SUBNET}
  ministack:   http://${LAN_IP}:${MINISTACK_PORT}
  stackport:   ${stackport}
  firewall:    ${firewall}
  aws cli:     ${aws}
  real infra:  ${infra}
  images:      ${MINISTACK_IMAGE}${image_note}
EOF
}

ensure_runtime() {
  if command -v "$RUNTIME" >/dev/null 2>&1; then
    RUNTIME_BIN=$(command -v "$RUNTIME")
    return 0
  fi
  [[ "$RUNTIME" == podman ]] || die "Docker is not installed. Install it, or run again without --runtime docker so Hearthline can install Podman."
  log "Installing Podman."
  case "$OS_FAMILY" in
    fedora) dnf install -y podman curl ca-certificates ;;
    debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y podman curl ca-certificates
      ;;
  esac
  need_cmd podman
  RUNTIME_BIN=$(command -v podman)
}

ensure_curl() {
  if command -v curl >/dev/null 2>&1; then
    CURL_BIN=$(command -v curl)
    return 0
  fi
  case "$OS_FAMILY" in
    fedora) dnf install -y curl ca-certificates ;;
    debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates
      ;;
  esac
  need_cmd curl
  CURL_BIN=$(command -v curl)
}

stop_previous_lab() {
  local uid runtime_dir home
  [[ "$USER_MODE" -eq 0 ]] || return 0
  [[ "$TARGET_USER" != root ]] || return 0
  home=$TARGET_HOME
  uid=$(id -u "$TARGET_USER")
  runtime_dir=/run/user/$uid
  if [[ -d "$runtime_dir" ]]; then
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user disable --now \
      ministack-autostart.service stackport.service ministack.service \
      hearthline-stackport.service hearthline-ministack.service >/dev/null 2>&1 || true
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" podman rm -f ministack stackport >/dev/null 2>&1 || true
    sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" docker rm -f ministack stackport >/dev/null 2>&1 || true
  fi
  local quadlet="$home/.config/containers/systemd"
  local name
  for name in ministack.container stackport.container; do
    if [[ -f "$quadlet/$name" ]]; then
      mv "$quadlet/$name" "$quadlet/$name.disabled-by-hearthline"
      log "Moved ${quadlet}/${name} aside so it does not grab the ports at login."
    fi
  done
  if [[ -d "$home/ministack/data/state" && -z "$(ls -A "$STATE_DIR" 2>/dev/null || true)" ]]; then
    cp -a "$home/ministack/data/state/." "$STATE_DIR/"
    log "Copied the previous MiniStack state into ${STATE_DIR}."
  fi
  if [[ -d "$home/ministack/data/s3" && -z "$(ls -A "$S3_DIR" 2>/dev/null || true)" ]]; then
    cp -a "$home/ministack/data/s3/." "$S3_DIR/"
  fi
}

enable_boot() {
  if [[ "$USER_MODE" -eq 1 ]]; then
    local linger_user=$TARGET_USER
    if [[ $EUID -eq 0 ]]; then
      loginctl enable-linger "$linger_user"
    elif sudo -n loginctl enable-linger "$linger_user"; then
      log "Linger is enabled for ${linger_user}."
    else
      warn "Linger is not enabled. The lab starts at login, not at boot, until you run: sudo loginctl enable-linger ${linger_user}"
      return 0
    fi
    log "Linger is enabled. The user manager starts the lab at boot."
    return 0
  fi
  if [[ "$RUNTIME" == docker ]]; then
    systemctl enable docker.service >/dev/null 2>&1 || systemctl enable docker.socket >/dev/null 2>&1 || true
  fi
}

reload_and_start() {
  if [[ "$USER_MODE" -eq 1 ]]; then
    local uid runtime_dir
    uid=$(id -u "$TARGET_USER")
    runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$uid}
    if [[ $EUID -eq 0 ]]; then
      sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user daemon-reload
      sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user enable --now hearthline-ministack.service
      if [[ "$WITH_STACKPORT" -eq 1 ]]; then
        sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="$runtime_dir" systemctl --user enable --now hearthline-stackport.service
      fi
    else
      systemctl --user daemon-reload
      systemctl --user enable --now hearthline-ministack.service
      if [[ "$WITH_STACKPORT" -eq 1 ]]; then
        systemctl --user enable --now hearthline-stackport.service
      fi
    fi
  else
    systemctl daemon-reload
    systemctl enable --now hearthline-ministack.service
    if [[ "$WITH_STACKPORT" -eq 1 ]]; then
      systemctl enable --now hearthline-stackport.service
    else
      systemctl disable --now hearthline-stackport.service >/dev/null 2>&1 || true
    fi
  fi
}

verify_lab() {
  local endpoint="http://${LAN_IP}:${MINISTACK_PORT}"
  curl -fsS --max-time 10 "$endpoint/_ministack/health" >/dev/null
  log "MiniStack is answering on ${endpoint}."
  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    curl -fsS --max-time 10 "http://${LAN_IP}:${STACKPORT_PORT}/api/health" >/dev/null
    log "StackPort is answering on http://${LAN_IP}:${STACKPORT_PORT}."
  fi
  if [[ "$WITH_AWSCLI" -eq 1 ]] && command -v aws >/dev/null 2>&1; then
    if [[ "$(id -un)" == "$TARGET_USER" ]]; then
      aws --profile hearthline sts get-caller-identity >/dev/null
    else
      sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" PATH="$PATH:/usr/local/bin:$TARGET_HOME/.local/bin" \
        aws --profile hearthline sts get-caller-identity >/dev/null
    fi
    log "AWS CLI profile hearthline can call MiniStack."
  fi
}

main() {
  local saved_args=("$@")
  parse_args "$@"
  detect_os
  detect_runtime "$RUNTIME"
  detect_network
  resolve_paths "$USER_MODE" "$PREFIX"
  if [[ "$PRINT_PLAN" -eq 1 ]]; then
    print_plan
    exit 0
  fi

  if [[ "$USER_MODE" -eq 0 && $EUID -ne 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then
      log "Root is required so the lab starts at boot."
      exec sudo "$SCRIPT_DIR/install.sh" "${saved_args[@]}"
    fi
    die "Run as root so MiniStack starts when the server boots: sudo ${SCRIPT_DIR}/install.sh"
  fi

  ensure_runtime
  ensure_curl
  if [[ "$USER_MODE" -eq 1 ]]; then
    WANTED_BY=default.target
  else
    WANTED_BY=multi-user.target
  fi

  log "Preparing ${DATA_DIR}."
  mkdir -p "$STATE_DIR" "$S3_DIR" "$STACKPORT_DIR" "$UNIT_DIR" "$CONFIG_DIR" "$BIN_DIR"
  "$RUNTIME_BIN" pull "$MINISTACK_IMAGE"
  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    "$RUNTIME_BIN" pull "$STACKPORT_IMAGE"
  fi

  write_env_files
  write_ministack_unit
  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    write_stackport_unit
  fi
  install_cli
  stop_previous_lab
  if [[ "$TARGET_USER" != root && $EUID -eq 0 && "$USER_MODE" -eq 1 ]]; then
    chown -R "$TARGET_USER:$(id -gn "$TARGET_USER")" "$CONFIG_DIR" "$DATA_DIR" "$UNIT_DIR/hearthline-ministack.service" "$BIN_DIR/hearthline"
    if [[ "$WITH_STACKPORT" -eq 1 ]]; then
      chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$UNIT_DIR/hearthline-stackport.service"
    fi
  fi

  if [[ "$WITH_FIREWALL" -eq 1 ]]; then
    open_lab_firewall
  fi
  if [[ "$WITH_AWSCLI" -eq 1 ]]; then
    if [[ "$USER_MODE" -eq 1 && $EUID -ne 0 ]]; then
      AWSCLI_INSTALL_DIR="$TARGET_HOME/.local/aws-cli"
      AWSCLI_BIN_DIR="$TARGET_HOME/.local/bin"
    fi
    install_awscli_if_missing
    configure_aws_profile "$TARGET_HOME" "$TARGET_USER"
  fi

  enable_boot
  reload_and_start
  verify_lab

  local stackport_line=""
  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    stackport_line="  StackPort   http://${LAN_IP}:${STACKPORT_PORT}"$'\n'
  fi
  cat <<EOF

Hearthline is up.
  MiniStack   http://${LAN_IP}:${MINISTACK_PORT}
${stackport_line}  AWS profile hearthline
  Data        ${DATA_DIR}
  Boot        ${BOOT_METHOD}

Try: hearthline status
EOF
}

main "$@"
