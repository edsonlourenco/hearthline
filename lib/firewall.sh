# Open the lab ports to the local subnet only.
# Author: Edson Lourenço

firewall_backend() {
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    echo firewalld
  elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    echo ufw
  elif command -v firewall-cmd >/dev/null 2>&1; then
    echo firewalld-inactive
  elif command -v ufw >/dev/null 2>&1; then
    echo ufw-inactive
  else
    echo none
  fi
}

firewall_zone() {
  local zone
  zone=$(firewall-cmd --get-zone-of-interface="$IFACE" 2>/dev/null || true)
  if [[ -z "$zone" ]]; then
    zone=$(firewall-cmd --get-default-zone 2>/dev/null || true)
  fi
  [[ -n "$zone" ]] || zone=public
  printf '%s' "$zone"
}

open_lab_firewall() {
  local backend rule zone changed=0
  backend=$(firewall_backend)
  mkdir -p "$CONFIG_DIR"
  : > "$CONFIG_DIR/firewall.rules"
  case "$backend" in
    firewalld)
      zone=$(firewall_zone)
      local port ports=("$MINISTACK_PORT")
      if [[ "$WITH_STACKPORT" -eq 1 ]]; then
        ports+=("$STACKPORT_PORT")
      fi
      for port in "${ports[@]}"; do
        rule="rule family=\"ipv4\" source address=\"${SUBNET}\" port port=\"${port}\" protocol=\"tcp\" accept"
        if ! firewall-cmd --permanent --zone="$zone" --query-rich-rule="$rule" >/dev/null 2>&1; then
          firewall-cmd --permanent --zone="$zone" --add-rich-rule="$rule"
          changed=1
        fi
        printf 'firewalld:%s:%s\n' "$zone" "$rule" >> "$CONFIG_DIR/firewall.rules"
      done
      if [[ "$changed" -eq 1 ]]; then
        firewall-cmd --reload
      fi
      log "Firewalld zone ${zone} accepts ${SUBNET} on the lab ports."
      ;;
    ufw)
      local port ports=("$MINISTACK_PORT")
      if [[ "$WITH_STACKPORT" -eq 1 ]]; then
        ports+=("$STACKPORT_PORT")
      fi
      for port in "${ports[@]}"; do
        if ! ufw status | grep -q "${port}/tcp"; then
          ufw allow from "$SUBNET" to any port "$port" proto tcp
        fi
        printf 'ufw:%s:%s\n' "$SUBNET" "$port" >> "$CONFIG_DIR/firewall.rules"
      done
      log "UFW accepts ${SUBNET} on the lab ports."
      ;;
    firewalld-inactive|ufw-inactive)
      warn "A firewall tool is installed but it is not active. The lab ports stay reachable on this host."
      ;;
    none)
      warn "No firewalld or UFW. If the host has another packet filter, open TCP ${MINISTACK_PORT} and ${STACKPORT_PORT} for ${SUBNET}."
      ;;
  esac
}

close_lab_firewall() {
  local rules=$1 line kind zone rule subnet port
  [[ -f "$rules" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kind=${line%%:*}
    case "$kind" in
      firewalld)
        zone=${line#firewalld:}
        zone=${zone%%:*}
        rule=${line#firewalld:${zone}:}
        firewall-cmd --permanent --zone="$zone" --remove-rich-rule="$rule" >/dev/null 2>&1 || true
        ;;
      ufw)
        subnet=${line#ufw:}
        port=${subnet##*:}
        subnet=${subnet%:*}
        ufw delete allow from "$subnet" to any port "$port" proto tcp >/dev/null 2>&1 || true
        ;;
    esac
  done < "$rules"
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}
