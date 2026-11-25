#!/usr/bin/env bash
#
# Build goose.
#
# Builds the Rust backend (`goose` CLI binary) and the Electron desktop app.
# The desktop app spawns the CLI binary it ships with, so the CLI is built and
# copied into ui/desktop/src/bin before the UI is packaged.
#
# Usage:
#   ./build.sh [target] [options]
#
# Targets:
#   make      Build distributables (installers/archives) with electron-forge. Default.
#   package   Build an unpacked app bundle (fast, good for local testing).
#   dev       Build the CLI and start the desktop app in development mode.
#   cli       Build only the Rust CLI binary.
#
# Options:
#   --debug              Build the CLI in debug mode instead of release.
#   --skip-cli           Do not rebuild the CLI; reuse target/<profile>/goose.
#   --skip-install       Do not run `pnpm install`.
#   --prepare-binaries   Run scripts/prepare-platform-binaries.js before packaging.
#   -h, --help           Show this help.
#
# Examples:
#   ./build.sh                 # release CLI + distributables
#   ./build.sh package         # release CLI + unpacked app
#   ./build.sh dev             # release CLI + run the app from source
#   ./build.sh make --debug    # debug CLI + distributables
#
# Notes:
#   On Linux the dev target auto-detects a non-setuid Electron sandbox helper and
#   disables the Chromium sandbox. If a Goose window is already open, close it
#   first: a second instance exits immediately (single-instance lock).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="make"
BUILD_MODE="release"
SKIP_CLI=0
SKIP_INSTALL=0
PREPARE_BINARIES=0

usage() {
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    make|package|dev|cli)
      TARGET="$1"
      ;;
    --debug)
      BUILD_MODE="debug"
      ;;
    --release)
      BUILD_MODE="release"
      ;;
    --skip-cli)
      SKIP_CLI=1
      ;;
    --skip-install)
      SKIP_INSTALL=1
      ;;
    --prepare-binaries)
      PREPARE_BINARIES=1
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage 1
      ;;
  esac
  shift
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Use the pinned toolchain (node, pnpm, cargo, just) when available.
if [[ "${NO_HERMIT:-0}" != "1" && -f "bin/activate-hermit" ]]; then
  # shellcheck disable=SC1091
  source bin/activate-hermit >/dev/null 2>&1 || true
fi

command -v cargo >/dev/null 2>&1 || die "cargo not found (source bin/activate-hermit or install Rust)"

case "$(uname -s)" in
  Darwin) HOST_OS="macos" ;;
  Linux)  HOST_OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) HOST_OS="windows" ;;
  *) HOST_OS="unknown" ;;
esac

build_cli() {
  if [[ "$SKIP_CLI" == "1" ]]; then
    log "Skipping CLI build (--skip-cli)"
    return
  fi

  if [[ "$BUILD_MODE" == "release" ]]; then
    log "Building goose CLI (release)"
    cargo build --release -p goose-cli --bin goose
  else
    log "Building goose CLI (debug)"
    cargo build -p goose-cli --bin goose
  fi

  # The desktop app bundles this binary under an extraResource.
  local bin_name="goose"
  [[ "$HOST_OS" == "windows" ]] && bin_name="goose.exe"
  local src="$SCRIPT_DIR/target/$BUILD_MODE/$bin_name"
  local dest_dir="$SCRIPT_DIR/ui/desktop/src/bin"
  [[ -f "$src" ]] || die "CLI binary not found at $src"

  mkdir -p "$dest_dir"
  # Remove before copying: overwriting a running executable in place is unsafe.
  rm -f "$dest_dir/goosed" "$dest_dir/goose" "$dest_dir/goose.exe"
  cp -p "$src" "$dest_dir/$bin_name"
  log "Copied CLI binary to ui/desktop/src/bin/$bin_name"
}

install_ui_deps() {
  if [[ "$SKIP_INSTALL" == "1" ]]; then
    log "Skipping pnpm install (--skip-install)"
    return
  fi
  command -v pnpm >/dev/null 2>&1 || die "pnpm not found (source bin/activate-hermit or install pnpm)"
  log "Installing desktop dependencies"
  (cd ui/desktop && pnpm install)
}

# Electron aborts on Linux when its sandbox helper is not setuid and the kernel
# forbids unprivileged user namespaces (Ubuntu 24.04+). Fall back to disabling
# the Chromium sandbox for local development runs.
ensure_electron_sandbox() {
  [[ "$HOST_OS" == "linux" ]] || return 0
  local sandbox="ui/node_modules/electron/dist/chrome-sandbox"
  if [[ -f "$sandbox" && ! -u "$sandbox" ]]; then
    log "Electron sandbox helper is not setuid; disabling the Chromium sandbox for this run"
    log "  permanent fix: sudo chown root:root $sandbox && sudo chmod 4755 $sandbox"
    export ELECTRON_DISABLE_SANDBOX=1
  fi
}

prepare_binaries() {
  [[ "$PREPARE_BINARIES" == "1" ]] || return 0
  command -v node >/dev/null 2>&1 || die "node not found"
  log "Preparing platform binaries"
  (cd ui/desktop && node scripts/prepare-platform-binaries.js)
}

package_app() {
  install_ui_deps
  prepare_binaries
  case "$TARGET" in
    make)
      log "Building distributables (electron-forge make)"
      (cd ui/desktop && pnpm run make)
      log "Artifacts are in ui/desktop/out"
      ;;
    package)
      log "Packaging app (electron-forge package)"
      (cd ui/desktop && pnpm run package)
      log "App bundle is in ui/desktop/out"
      ;;
    dev)
      log "Starting desktop app in development mode"
      ensure_electron_sandbox
      log "Note: close any other running Goose window first; a second instance exits immediately"
      (cd ui/desktop && pnpm run start-gui)
      ;;
  esac
}

log "goose build — target=$TARGET mode=$BUILD_MODE host=$HOST_OS"

if [[ "$TARGET" == "cli" ]]; then
  build_cli
  log "Done: target/$BUILD_MODE/goose"
  exit 0
fi

build_cli
package_app
log "Build complete"
