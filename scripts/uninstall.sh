#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SCOPE="@dev-sprouts"
DEFAULT_REGISTRY_URL="https://npm.pkg.github.com"

SCOPE="$DEFAULT_SCOPE"
REGISTRY_URL="$DEFAULT_REGISTRY_URL"
PACKAGE_NAME=""
NPMRC_PATH="${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
REMOVE_REGISTRY="false"
PURGE_CONFIG="false"
ASSUME_YES="false"
DRY_RUN="false"

AUTOCOMPLETE_BEGIN_MARKER="# >>> devsprouts autocomplete >>>"
AUTOCOMPLETE_END_MARKER="# <<< devsprouts autocomplete <<<"
LEGACY_AUTOCOMPLETE_MARKER="# devsprouts autocomplete setup"

print_help() {
  cat <<'USAGE'
Uninstall devsprouts-cli and clean optional local setup.

Usage:
  ./scripts/uninstall.sh [options]
  curl -fsSL https://raw.githubusercontent.com/Dev-Sprouts/devsprouts-cli-scripts/main/scripts/uninstall.sh | bash

Options:
  --scope <scope>         npm scope (default: @dev-sprouts)
  --registry <url>        npm registry URL used for auth token key (default: https://npm.pkg.github.com)
  --userconfig <path>     npm user config file path (default: ~/.npmrc)
  --package <name>        package to uninstall globally (default: <scope>/devsprouts-cli)
  --remove-registry       remove npm registry/token entries from userconfig
  --purge-config          remove devsprouts config/cache directories
  --yes                   skip interactive confirmations
  --dry-run               print actions without changing anything
  -h, --help              show this help
USAGE
}

require_value() {
  local flag="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for $flag" >&2
    print_help
    exit 1
  fi
}

run_or_print() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "[dry-run]"
    printf " %q" "$@"
    printf "\n"
    return 0
  fi
  "$@"
}

confirm_if_needed() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "true" || ! -t 0 ]]; then
    return 0
  fi

  local answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

registry_auth_key() {
  local registry="$1"
  registry="${registry#http://}"
  registry="${registry#https://}"
  registry="${registry%%\?*}"
  registry="${registry%%\#*}"
  registry="${registry%/}"
  echo "//$registry/:_authToken"
}

remove_autocomplete_from_rc() {
  local rc_file="$1"
  if [[ ! -f "$rc_file" ]]; then
    return
  fi

  local tmp_rc
  tmp_rc="$(mktemp -t devsprouts-rc-clean.XXXXXX)"
  awk -v begin="$AUTOCOMPLETE_BEGIN_MARKER" -v end="$AUTOCOMPLETE_END_MARKER" -v legacy="$LEGACY_AUTOCOMPLETE_MARKER" '
    BEGIN { in_block=0 }
    index($0, begin) { in_block=1; next }
    index($0, end) { in_block=0; next }
    in_block { next }
    index($0, legacy) { next }
    { print }
  ' "$rc_file" > "$tmp_rc"

  if cmp -s "$rc_file" "$tmp_rc"; then
    rm -f "$tmp_rc"
    echo "No devsprouts autocomplete entries found in $rc_file"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    rm -f "$tmp_rc"
    echo "Would remove devsprouts autocomplete entries from $rc_file"
    return
  fi

  mv "$tmp_rc" "$rc_file"
  echo "Removed devsprouts autocomplete entries from $rc_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      require_value "$1" "${2:-}"
      SCOPE="$2"
      shift 2
      ;;
    --registry)
      require_value "$1" "${2:-}"
      REGISTRY_URL="$2"
      shift 2
      ;;
    --userconfig)
      require_value "$1" "${2:-}"
      NPMRC_PATH="$2"
      shift 2
      ;;
    --package)
      require_value "$1" "${2:-}"
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --remove-registry)
      REMOVE_REGISTRY="true"
      shift
      ;;
    --purge-config)
      PURGE_CONFIG="true"
      shift
      ;;
    --yes)
      ASSUME_YES="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
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

if [[ "$SCOPE" != @* ]]; then
  SCOPE="@$SCOPE"
fi

if [[ -z "$PACKAGE_NAME" ]]; then
  PACKAGE_NAME="$SCOPE/devsprouts-cli"
fi

NPM_AVAILABLE="false"
if command -v npm >/dev/null 2>&1; then
  NPM_AVAILABLE="true"
fi

echo "Step 1/4: uninstalling $PACKAGE_NAME..."
if [[ "$NPM_AVAILABLE" == "true" ]]; then
  if npm list -g "$PACKAGE_NAME" --depth=0 >/dev/null 2>&1; then
    run_or_print npm uninstall -g "$PACKAGE_NAME"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "Would uninstall $PACKAGE_NAME globally."
    else
      echo "Uninstalled $PACKAGE_NAME globally."
    fi
  else
    echo "$PACKAGE_NAME is not installed globally. Skipping package uninstall."
  fi
else
  echo "npm is not available in PATH. Skipping package uninstall."
fi

echo "Step 2/4: removing autocomplete setup from shell rc files..."
remove_autocomplete_from_rc "$HOME/.zshrc"
remove_autocomplete_from_rc "$HOME/.bashrc"

echo "Step 3/4: removing npm registry configuration..."
if [[ "$REMOVE_REGISTRY" == "true" ]]; then
  if [[ "$NPM_AVAILABLE" != "true" ]]; then
    echo "npm is not available in PATH. Skipping registry cleanup."
  elif confirm_if_needed "Remove npm registry entries for scope '$SCOPE' in '$NPMRC_PATH'?"; then
    auth_key="$(registry_auth_key "$REGISTRY_URL")"
    if [[ "$DRY_RUN" == "true" ]]; then
      run_or_print npm config delete "$SCOPE:registry" --userconfig "$NPMRC_PATH"
      run_or_print npm config delete "$auth_key" --userconfig "$NPMRC_PATH"
      echo "Would remove npm registry entries for scope '$SCOPE'."
    else
      npm config delete "$SCOPE:registry" --userconfig "$NPMRC_PATH" >/dev/null 2>&1 || true
      npm config delete "$auth_key" --userconfig "$NPMRC_PATH" >/dev/null 2>&1 || true
      echo "Removed npm registry entries for scope '$SCOPE'."
    fi
  else
    echo "Skipped npm registry cleanup."
  fi
else
  echo "Skipped (use --remove-registry to enable)."
fi

echo "Step 4/4: removing devsprouts local config/cache..."
if [[ "$PURGE_CONFIG" == "true" ]]; then
  if confirm_if_needed "Remove local devsprouts config/cache directories?"; then
    for path in "$HOME/.config/devsprouts" "$HOME/.cache/devsprouts" "$HOME/Library/Caches/devsprouts"; do
      if [[ -e "$path" ]]; then
        run_or_print rm -rf "$path"
        if [[ "$DRY_RUN" == "true" ]]; then
          echo "Would remove $path"
        else
          echo "Removed $path"
        fi
      else
        echo "Not found: $path"
      fi
    done
  else
    echo "Skipped config/cache purge."
  fi
else
  echo "Skipped (use --purge-config to enable)."
fi

echo "Uninstall completed."
