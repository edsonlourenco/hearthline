# AWS CLI v2 and a lab profile that speaks to MiniStack.
# Author: Edson Lourenço

install_awscli_if_missing() {
  if command -v aws >/dev/null 2>&1; then
    log "AWS CLI is already installed: $(command -v aws)"
    return 0
  fi
  local arch tmp
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64) ;;
    *) die "No AWS CLI build for architecture ${arch}." ;;
  esac
  need_cmd curl
  if ! command -v unzip >/dev/null 2>&1; then
    case "$OS_FAMILY" in
      fedora) dnf install -y unzip ;;
      debian) DEBIAN_FRONTEND=noninteractive apt-get install -y unzip ;;
    esac
  fi
  tmp=$(mktemp -d)
  log "Installing AWS CLI v2 for ${arch}."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  if [[ -n "${AWSCLI_BIN_DIR:-}" ]]; then
    "$tmp/aws/install" -i "$AWSCLI_INSTALL_DIR" -b "$AWSCLI_BIN_DIR" --update
  else
    "$tmp/aws/install" --update
  fi
  rm -rf "$tmp"
  need_cmd aws
}

# Drop one INI section and append a fresh copy. A section runs until the next header.
replace_ini_block() {
  local file=$1 header=$2 body=$3 tmp
  tmp=$(mktemp)
  if [[ -f "$file" ]]; then
    awk -v header="$header" '
      $0 == header { skip = 1; next }
      skip && /^\[/ { skip = 0 }
      skip { next }
      { print }
    ' "$file" > "$tmp"
  fi
  {
    if [[ -s "$tmp" ]]; then
      cat "$tmp"
      printf '\n'
    fi
    printf '%s\n%s\n' "$header" "$body"
  } > "$file"
  rm -f "$tmp"
}

default_profile_is_free() {
  local cred=$1 key
  [[ -f "$cred" ]] || return 0
  key=$(awk '
    $0 == "[default]" { found = 1; next }
    found && /^\[/ { exit }
    found && $0 ~ /^aws_access_key_id[[:space:]]*=/ {
      sub(/^aws_access_key_id[[:space:]]*=[[:space:]]*/, "")
      print
      exit
    }
  ' "$cred")
  [[ -z "$key" || "$key" == "test" ]]
}

configure_aws_profile() {
  local home=$1 user=$2 endpoint profile_body default_body
  endpoint="http://${LAN_IP}:${MINISTACK_PORT}"
  mkdir -p "$home/.aws"
  chmod 700 "$home/.aws"
  profile_body=$(cat <<EOF
region = ${REGION}
output = json
endpoint_url = ${endpoint}
s3 =
    addressing_style = path
EOF
)
  replace_ini_block "$home/.aws/config" "[profile hearthline]" "$profile_body"
  replace_ini_block "$home/.aws/credentials" "[hearthline]" "$(cat <<EOF
aws_access_key_id = ${AWS_KEY}
aws_secret_access_key = ${AWS_SECRET}
EOF
)"
  if default_profile_is_free "$home/.aws/credentials"; then
    default_body=$profile_body
    replace_ini_block "$home/.aws/config" "[default]" "$default_body"
    replace_ini_block "$home/.aws/credentials" "[default]" "$(cat <<EOF
aws_access_key_id = ${AWS_KEY}
aws_secret_access_key = ${AWS_SECRET}
EOF
)"
    log "AWS profile default and profile hearthline point at ${endpoint}."
  else
    log "Left the default AWS profile untouched. Use: aws --profile hearthline"
  fi
  chmod 600 "$home/.aws/config" "$home/.aws/credentials"
  if [[ "$user" != root && $EUID -eq 0 ]]; then
    chown -R "$user:$(id -gn "$user")" "$home/.aws"
  fi
}
