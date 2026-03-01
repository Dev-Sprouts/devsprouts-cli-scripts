#!/usr/bin/env bash
set -euo pipefail

REGISTRY_URL="https://npm.pkg.github.com"
NPMRC_PATH="${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
SCOPE=""
PACKAGE_NAME=""
INSTALL_AFTER_SETUP="false"

print_help() {
  cat <<'USAGE'
Configure npm to install private packages from GitHub Packages using your `gh` auth token.

Usage:
  ./scripts/setup-private-registry.sh [options]

Options:
  --scope <scope>         npm scope to configure (example: @dev-sprouts)
  --registry <url>        npm registry URL (default: https://npm.pkg.github.com)
  --userconfig <path>     npm user config file path (default: ~/.npmrc)
  --package <name>        package to install globally after setup (default: <scope>/devsprouts-cli)
  --install               install the package globally after registry setup
  -h, --help              show this help
USAGE
}

parse_scope_from_remote() {
  local remote_url
  remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"

  if [[ -z "$remote_url" ]]; then
    return 1
  fi

  local owner
  owner="$(echo "$remote_url" | sed -E 's#(git@github.com:|https://github.com/|ssh://git@github.com/)([^/]+)/.*#\2#')"

  if [[ -z "$owner" || "$owner" == "$remote_url" ]]; then
    return 1
  fi

  echo "@$(echo "$owner" | tr '[:upper:]' '[:lower:]')"
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="$2"
      shift 2
      ;;
    --registry)
      REGISTRY_URL="$2"
      shift 2
      ;;
    --userconfig)
      NPMRC_PATH="$2"
      shift 2
      ;;
    --package)
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --install)
      INSTALL_AFTER_SETUP="true"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      print_help
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required. Install it from https://cli.github.com"
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but was not found in PATH."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "You are not authenticated in gh. Run: gh auth login"
  exit 1
fi

if [[ -z "$SCOPE" ]]; then
  if ! SCOPE="$(parse_scope_from_remote)"; then
    SCOPE="@dev-sprouts"
  fi
fi

if [[ "$SCOPE" != @* ]]; then
  SCOPE="@$SCOPE"
fi

if [[ -z "$PACKAGE_NAME" ]]; then
  PACKAGE_NAME="$SCOPE/devsprouts-cli"
fi

GH_TOKEN="$(gh auth token)"

npm config set "$SCOPE:registry" "$REGISTRY_URL" --userconfig "$NPMRC_PATH"
npm config set "//npm.pkg.github.com/:_authToken" "$GH_TOKEN" --userconfig "$NPMRC_PATH"

echo "Configured npm registry for scope '$SCOPE' in '$NPMRC_PATH'."
echo "You can now install private packages from GitHub Packages."

echo "Example: npm install -g $PACKAGE_NAME"

if [[ "$INSTALL_AFTER_SETUP" == "true" ]]; then
  npm install -g "$PACKAGE_NAME"
  echo "Installed $PACKAGE_NAME globally."
fi
