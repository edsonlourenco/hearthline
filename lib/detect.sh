# Host, runtime, and network detection.
# Author: Edson Lourenço

detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID=${ID:-unknown}
  OS_PRETTY=${PRETTY_NAME:-$OS_ID}
  OS_VERSION=${VERSION_ID:-}
  case "$OS_ID" in
    fedora|rhel|centos|rocky|almalinux|ol|amzn)
      OS_FAMILY=fedora
      ;;
    ubuntu|debian|linuxmint|pop|raspbian)
      OS_FAMILY=debian
      ;;
    *)
      die "Unsupported distribution: ${OS_PRETTY}. Hearthline supports Fedora and Ubuntu, including their close relatives (RHEL, Debian)."
      ;;
  esac
}

detect_runtime() {
  local requested=${1:-}
  if [[ -n "$requested" ]]; then
    case "$requested" in
      podman|docker) RUNTIME=$requested ;;
      *) die "Runtime must be podman or docker, not: $requested" ;;
    esac
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
  else
    RUNTIME=podman
    RUNTIME_NEEDS_INSTALL=1
  fi
}

runtime_bin_path() {
  if command -v "$RUNTIME" >/dev/null 2>&1; then
    command -v "$RUNTIME"
    return 0
  fi
  case "$RUNTIME" in
    podman) echo /usr/bin/podman ;;
    docker) echo /usr/bin/docker ;;
  esac
}

detect_network() {
  need_cmd ip
  if [[ -z "${IFACE:-}" ]]; then
    IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')
  fi
  [[ -n "${IFACE:-}" ]] || die "No default IPv4 route. Pass --lan-ip and --iface."

  if [[ -z "${LAN_IP:-}" ]]; then
    LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')
  fi
  [[ -n "${LAN_IP:-}" ]] || die "Could not detect the LAN address. Pass --lan-ip."

  local cidr prefix a b c d
  cidr=$(ip -4 -o addr show dev "$IFACE" | awk '{print $4; exit}')
  if [[ -z "${SUBNET:-}" ]]; then
    if [[ -z "$cidr" ]]; then
      die "Could not read the prefix on ${IFACE}. Pass --subnet, for example 192.168.1.0/24."
    fi
    prefix=${cidr#*/}
    IFS=. read -r a b c d <<<"${cidr%/*}"
    case "$prefix" in
      8) SUBNET="${a}.0.0.0/8" ;;
      16) SUBNET="${a}.${b}.0.0/16" ;;
      24) SUBNET="${a}.${b}.${c}.0/24" ;;
      *)
        if command -v python3 >/dev/null 2>&1; then
          SUBNET=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$cidr")
        else
          die "Prefix /${prefix} needs python3, or pass --subnet."
        fi
        ;;
    esac
  fi
}

volume_suffix() {
  if [[ -f /sys/fs/selinux/enforce ]]; then
    printf ':Z'
  fi
}

resolve_paths() {
  local user_mode=$1
  local prefix=${2:-}
  if [[ "$user_mode" -eq 1 ]]; then
    TARGET_USER=${SUDO_USER:-$USER}
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    [[ -n "$TARGET_HOME" ]] || die "Cannot resolve the home directory of ${TARGET_USER}."
    CONFIG_DIR="$TARGET_HOME/.config/hearthline"
    DATA_DIR=${prefix:-$TARGET_HOME/.local/share/hearthline}
    UNIT_DIR="$TARGET_HOME/.config/systemd/user"
    BIN_DIR="$TARGET_HOME/.local/bin"
    BOOT_METHOD="linger"
  else
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
      TARGET_USER=$SUDO_USER
    elif [[ "$(id -un)" != root ]]; then
      TARGET_USER=$(id -un)
    else
      TARGET_USER=root
    fi
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    [[ -n "$TARGET_HOME" ]] || TARGET_HOME=/root
    CONFIG_DIR=/etc/hearthline
    DATA_DIR=${prefix:-/var/lib/hearthline}
    UNIT_DIR=/etc/systemd/system
    BIN_DIR=/usr/local/bin
    BOOT_METHOD=systemd
  fi
  STATE_DIR="$DATA_DIR/ministack/state"
  S3_DIR="$DATA_DIR/ministack/s3"
  STACKPORT_DIR="$DATA_DIR/stackport"
}
