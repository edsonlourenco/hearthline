# systemd units that keep the lab in the foreground, so a reboot starts it again.
# Author: Edson Lourenço

write_env_files() {
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$S3_DIR" "$STACKPORT_DIR" "$BIN_DIR"
  cat > "$CONFIG_DIR/hearthline.env" <<EOF
# Hearthline lab settings. Written by install.sh.
# Author: Edson Lourenço
RUNTIME=${RUNTIME}
RUNTIME_BIN=${RUNTIME_BIN}
OS_FAMILY=${OS_FAMILY}
LAN_IP=${LAN_IP}
SUBNET=${SUBNET}
IFACE=${IFACE}
REGION=${REGION}
MINISTACK_PORT=${MINISTACK_PORT}
STACKPORT_PORT=${STACKPORT_PORT}
WITH_STACKPORT=${WITH_STACKPORT}
DATA_DIR=${DATA_DIR}
CONFIG_DIR=${CONFIG_DIR}
BOOT_METHOD=${BOOT_METHOD}
MINISTACK_IMAGE=${MINISTACK_IMAGE}
STACKPORT_IMAGE=${STACKPORT_IMAGE}
AWS_ACCESS_KEY_ID=${AWS_KEY}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET}
TARGET_USER=${TARGET_USER}
EOF
  cat > "$CONFIG_DIR/env.sh" <<EOF
# Source this file to aim the current shell at the lab.
#   source ${CONFIG_DIR}/env.sh
export AWS_ACCESS_KEY_ID=${AWS_KEY}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET}
export AWS_DEFAULT_REGION=${REGION}
export AWS_ENDPOINT_URL=http://${LAN_IP}:${MINISTACK_PORT}
export AWS_PROFILE=hearthline
EOF
  chmod 644 "$CONFIG_DIR/hearthline.env" "$CONFIG_DIR/env.sh"

  if [[ "$WITH_STACKPORT" -eq 1 ]]; then
    cat > "$STACKPORT_DIR/endpoints.json" <<EOF
{
  "version": 2,
  "default": "default",
  "deleted_env_names": [],
  "endpoints": {
    "default": {
      "url": "http://${LAN_IP}:${MINISTACK_PORT}",
      "source": "env",
      "region": "${REGION}",
      "auth_type": "default",
      "auth_profile": null,
      "auth_access_key_id": null,
      "auth_secret_access_key": null
    }
  }
}
EOF
  fi
}

real_infra_args() {
  local socket=""
  [[ "${REAL_INFRA:-0}" -eq 1 ]] || return 0
  if [[ "$RUNTIME" == docker && -S /var/run/docker.sock ]]; then
    socket=/var/run/docker.sock
  elif [[ -S /run/podman/podman.sock ]]; then
    socket=/run/podman/podman.sock
  elif [[ -S /var/run/docker.sock ]]; then
    socket=/var/run/docker.sock
  fi
  if [[ -z "$socket" ]]; then
    warn "Real-infra mode needs a container engine socket. Continuing without it."
    return 0
  fi
  printf -- '-v %s:/var/run/docker.sock' "$socket"
}

write_ministack_unit() {
  local suffix infra="" delegate=""
  suffix=$(volume_suffix)
  if [[ "${REAL_INFRA:-0}" -eq 1 ]]; then
    infra=$(real_infra_args || true)
    if [[ -n "$infra" ]]; then
      infra=" \\
  ${infra}"
    fi
  fi
  if [[ "$RUNTIME" == podman ]]; then
    delegate=$'Delegate=yes\n'
  fi
  cat > "$UNIT_DIR/hearthline-ministack.service" <<EOF
[Unit]
Description=Hearthline MiniStack local AWS emulator
Documentation=https://github.com/edsonlourenco/hearthline
After=network-online.target
Wants=network-online.target

[Service]
${delegate}Restart=always
RestartSec=3
TimeoutStartSec=180
TimeoutStopSec=40
ExecStartPre=-${RUNTIME_BIN} rm -f hearthline-ministack
ExecStart=${RUNTIME_BIN} run --name hearthline-ministack --rm \\
  -p ${MINISTACK_PORT}:4566 \\
  -e GATEWAY_PORT=4566 \\
  -e LOG_LEVEL=INFO \\
  -e PERSIST_STATE=1 \\
  -e S3_PERSIST=1 \\
  -e MINISTACK_REGION=${REGION} \\
  -e MINISTACK_ACCOUNT_ID=000000000000 \\
  -e LAMBDA_EXECUTOR=local \\
  -v ${STATE_DIR}:/tmp/ministack-state${suffix} \\
  -v ${S3_DIR}:/tmp/ministack-data/s3${suffix}${infra} \\
  ${MINISTACK_IMAGE}
ExecStop=-${RUNTIME_BIN} stop -t 20 hearthline-ministack
ExecStartPost=${CURL_BIN} -fsS --retry 30 --retry-delay 1 --retry-connrefused http://127.0.0.1:${MINISTACK_PORT}/_ministack/health

[Install]
WantedBy=${WANTED_BY}
EOF
}

write_stackport_unit() {
  local suffix delegate=""
  suffix=$(volume_suffix)
  if [[ "$RUNTIME" == podman ]]; then
    delegate=$'Delegate=yes\n'
  fi
  cat > "$UNIT_DIR/hearthline-stackport.service" <<EOF
[Unit]
Description=Hearthline StackPort console for MiniStack
Documentation=https://github.com/edsonlourenco/hearthline
After=hearthline-ministack.service
Requires=hearthline-ministack.service

[Service]
${delegate}Restart=always
RestartSec=3
TimeoutStartSec=180
TimeoutStopSec=30
ExecStartPre=${CURL_BIN} -fsS --retry 40 --retry-delay 1 --retry-connrefused http://127.0.0.1:${MINISTACK_PORT}/_ministack/health
ExecStartPre=-${RUNTIME_BIN} rm -f hearthline-stackport
ExecStart=${RUNTIME_BIN} run --name hearthline-stackport --rm \\
  --network host \\
  -e AWS_ENDPOINT_URL=http://${LAN_IP}:${MINISTACK_PORT} \\
  -e AWS_REGION=${REGION} \\
  -e AWS_DEFAULT_REGION=${REGION} \\
  -e AWS_ACCESS_KEY_ID=${AWS_KEY} \\
  -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET} \\
  -e STACKPORT_ALLOW_WRITES=true \\
  -e STACKPORT_PORT=${STACKPORT_PORT} \\
  -e STACKPORT_DATA_DIR=/data \\
  -v ${STACKPORT_DIR}:/data${suffix} \\
  ${STACKPORT_IMAGE}
ExecStop=-${RUNTIME_BIN} stop -t 15 hearthline-stackport
ExecStartPost=${CURL_BIN} -fsS --retry 30 --retry-delay 1 --retry-connrefused http://127.0.0.1:${STACKPORT_PORT}/api/health

[Install]
WantedBy=${WANTED_BY}
EOF
}

install_cli() {
  cp "$SCRIPT_DIR/hearthline" "$BIN_DIR/hearthline"
  chmod 755 "$BIN_DIR/hearthline"
}
