#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO="Dev-Sprouts/devsprouts-cli-scripts"
DEFAULT_REF="main"

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd || pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-private-registry.sh"

SHELL_NAME=""
REPO_SLUG="$DEFAULT_REPO"
REF_NAME="$DEFAULT_REF"
SETUP_SCRIPT_URL=""
SETUP_ARGS=()
TMP_SETUP_SCRIPT=""

print_help() {
  cat <<'USAGE'
Install devsprouts-cli end-to-end:
1) Configure private npm registry and install package globally
2) Configure shell autocomplete automatically
3) Run `devsprouts config init`
4) Run `devsprouts doctor` as final verification

Usage:
  ./scripts/install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/Dev-Sprouts/devsprouts-cli-scripts/main/scripts/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/Dev-Sprouts/devsprouts-cli-scripts/main/scripts/install.sh | bash -s -- --scope @dev-sprouts

Options:
  --shell <zsh|bash>     Shell for autocomplete setup (default: detect from $SHELL)
  --repo <owner/repo>    Repo used to fetch setup script when running via curl (default: Dev-Sprouts/devsprouts-cli-scripts)
  --ref <git-ref>        Git ref used to fetch setup script (default: main)
  --setup-script-url     Full URL for setup-private-registry.sh (overrides --repo/--ref)
  --scope <scope>        Forwarded to setup-private-registry.sh
  --registry <url>       Forwarded to setup-private-registry.sh
  --userconfig <path>    Forwarded to setup-private-registry.sh
  --package <name>       Forwarded to setup-private-registry.sh
  -h, --help             Show this help
USAGE
}

detect_shell() {
  if [[ -n "$SHELL_NAME" ]]; then
    echo "$SHELL_NAME"
    return
  fi

  local detected
  detected="$(basename "${SHELL:-}")"
  case "$detected" in
    zsh|bash)
      echo "$detected"
      ;;
    *)
      echo "zsh"
      ;;
  esac
}

resolve_devsprouts_bin() {
  if command -v devsprouts >/dev/null 2>&1; then
    command -v devsprouts
    return
  fi

  local global_prefix
  global_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ -n "$global_prefix" && -x "$global_prefix/bin/devsprouts" ]]; then
    echo "$global_prefix/bin/devsprouts"
    return
  fi

  echo "Unable to find 'devsprouts' after install. Ensure your npm global bin is in PATH." >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMP_SETUP_SCRIPT" && -f "$TMP_SETUP_SCRIPT" ]]; then
    rm -f "$TMP_SETUP_SCRIPT"
  fi
}

ensure_setup_script() {
  if [[ -x "$SETUP_SCRIPT" ]]; then
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download setup-private-registry.sh when running remotely." >&2
    exit 1
  fi

  local url="$SETUP_SCRIPT_URL"
  if [[ -z "$url" ]]; then
    url="https://raw.githubusercontent.com/${REPO_SLUG}/${REF_NAME}/scripts/setup-private-registry.sh"
  fi

  TMP_SETUP_SCRIPT="$(mktemp -t devsprouts-setup-private-registry.XXXXXX.sh)"
  curl -fsSL "$url" -o "$TMP_SETUP_SCRIPT"
  chmod +x "$TMP_SETUP_SCRIPT"
  SETUP_SCRIPT="$TMP_SETUP_SCRIPT"
}

setup_autocomplete() {
  local devsprouts_bin="$1"
  local shell_name="$2"
  local rc_file=""

  case "$shell_name" in
    zsh)
      rc_file="$HOME/.zshrc"
      ;;
    bash)
      rc_file="$HOME/.bashrc"
      ;;
    *)
      echo "Unsupported shell '$shell_name' for automatic autocomplete setup." >&2
      echo "Run manually: $devsprouts_bin autocomplete $shell_name" >&2
      return
      ;;
  esac

  "$devsprouts_bin" autocomplete "$shell_name" --refresh-cache >/dev/null 2>&1 || true

  local snippet
  snippet="$("$devsprouts_bin" autocomplete script "$shell_name" | sed '/^[[:space:]]*$/d' | tail -n 1)"
  if [[ -z "$snippet" ]]; then
    echo "Could not generate autocomplete script for shell '$shell_name'." >&2
    return
  fi

  touch "$rc_file"
  if grep -Fq "# devsprouts autocomplete setup" "$rc_file"; then
    echo "Autocomplete already configured in $rc_file"
  else
    printf "\n%s\n" "$snippet" >> "$rc_file"
    echo "Added autocomplete setup to $rc_file"
  fi

  # shellcheck disable=SC1090
  source "$rc_file" || true
}

run_config_init() {
  local devsprouts_bin="$1"
  local config_path="${HOME}/.config/devsprouts/config.json"

  if [[ -f "$config_path" ]]; then
    if [[ -t 0 ]]; then
      local answer
      read -r -p "Global config already exists at $config_path. Overwrite with --force? [y/N] " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        "$devsprouts_bin" config init --force
      else
        echo "Skipping 'devsprouts config init'."
      fi
      return
    fi

    echo "Skipping 'devsprouts config init' because config already exists at $config_path."
    return
  fi

  "$devsprouts_bin" config init
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      SHELL_NAME="$2"
      shift 2
      ;;
    --repo)
      REPO_SLUG="$2"
      shift 2
      ;;
    --ref)
      REF_NAME="$2"
      shift 2
      ;;
    --setup-script-url)
      SETUP_SCRIPT_URL="$2"
      shift 2
      ;;
    --scope|--registry|--userconfig|--package)
      SETUP_ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_help
      exit 1
      ;;
  esac
done

trap cleanup EXIT
ensure_setup_script

echo "Step 1/4: configuring private npm registry and installing devsprouts-cli..."
if ((${#SETUP_ARGS[@]})); then
  "$SETUP_SCRIPT" "${SETUP_ARGS[@]}" --install
else
  "$SETUP_SCRIPT" --install
fi

DEVSPROUTS_BIN="$(resolve_devsprouts_bin)"
SELECTED_SHELL="$(detect_shell)"

echo "Step 2/4: configuring autocomplete for $SELECTED_SHELL..."
setup_autocomplete "$DEVSPROUTS_BIN" "$SELECTED_SHELL"

echo "Step 3/4: running 'devsprouts config init'..."
run_config_init "$DEVSPROUTS_BIN"

echo "Step 4/4: running 'devsprouts doctor'..."
"$DEVSPROUTS_BIN" doctor

echo "Installation completed."
