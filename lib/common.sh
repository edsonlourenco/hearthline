# Shared helpers for Hearthline.
# Author: Edson Lourenço

if [[ -z "${HEARTHLINE_COMMON_LOADED:-}" ]]; then
  HEARTHLINE_COMMON_LOADED=1

  if [[ -t 1 ]]; then
    HEARTHLINE_BLUE=$'\033[1;34m'
    HEARTHLINE_YELLOW=$'\033[1;33m'
    HEARTHLINE_RED=$'\033[1;31m'
    HEARTHLINE_RESET=$'\033[0m'
  else
    HEARTHLINE_BLUE=""
    HEARTHLINE_YELLOW=""
    HEARTHLINE_RED=""
    HEARTHLINE_RESET=""
  fi

  log() { printf '%s==>%s %s\n' "$HEARTHLINE_BLUE" "$HEARTHLINE_RESET" "$*"; }
  warn() { printf '%swarning:%s %s\n' "$HEARTHLINE_YELLOW" "$HEARTHLINE_RESET" "$*" >&2; }
  die() { printf '%serror:%s %s\n' "$HEARTHLINE_RED" "$HEARTHLINE_RESET" "$*" >&2; exit 1; }

  need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
  }
fi
