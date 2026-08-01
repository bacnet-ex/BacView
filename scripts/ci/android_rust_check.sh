#!/usr/bin/env bash
# Tier 1: compile Android-only Rust (cfg target_os=android) for selected targets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}/src-tauri"

# icons/ is gitignored; tauri::generate_context! needs them at compile time.
if [[ ! -f icons/32x32.png ]]; then
  echo "Generating Tauri icons from priv/static/icon.png…"
  if ! command -v cargo-tauri >/dev/null 2>&1 && ! cargo tauri --version >/dev/null 2>&1; then
    cargo install tauri-cli --version "^2.11.4" --locked
  fi
  cargo tauri icon ../priv/static/icon.png
fi

if [[ -z "${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}" ]]; then
  echo "ERROR: ANDROID_NDK_HOME or ANDROID_NDK_ROOT must be set (run scripts/ci/android_setup_sdk.sh)" >&2
  exit 1
fi
NDK="${ANDROID_NDK_HOME:-$ANDROID_NDK_ROOT}"

HOST_TAG="${ANDROID_NDK_HOST_TAG:-linux-x86_64}"
PREBUILT="${NDK}/toolchains/llvm/prebuilt/${HOST_TAG}"
[[ -d "${PREBUILT}" ]] || {
  echo "ERROR: NDK prebuilt toolchain missing: ${PREBUILT}" >&2
  exit 1
}

API="${ANDROID_API_LEVEL:-24}"

# Map Rust target → NDK clang triple prefix
linker_for() {
  case "$1" in
    aarch64-linux-android) echo "${PREBUILT}/bin/aarch64-linux-android${API}-clang" ;;
    armv7-linux-androideabi) echo "${PREBUILT}/bin/armv7a-linux-androideabi${API}-clang" ;;
    x86_64-linux-android) echo "${PREBUILT}/bin/x86_64-linux-android${API}-clang" ;;
    i686-linux-android) echo "${PREBUILT}/bin/i686-linux-android${API}-clang" ;;
    *)
      echo "ERROR: unsupported Rust target: $1" >&2
      return 1
      ;;
  esac
}

TARGETS=(
  aarch64-linux-android
  x86_64-linux-android
)

if [[ "${ANDROID_RUST_INCLUDE_ARMV7:-0}" == "1" ]]; then
  TARGETS+=(armv7-linux-androideabi)
fi

for t in "${TARGETS[@]}"; do
  rustup target add "${t}"
done

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
# shellcheck disable=SC1091
[[ -f "${CARGO_HOME}/env" ]] && . "${CARGO_HOME}/env"

for t in "${TARGETS[@]}"; do
  linker="$(linker_for "${t}")"
  [[ -x "${linker}" ]] || {
    echo "ERROR: linker not executable: ${linker}" >&2
    exit 1
  }
  ar="${PREBUILT}/bin/llvm-ar"
  echo "==> cargo check --target ${t}"
  cargo check --target "${t}" \
    --config "target.${t}.linker=\"${linker}\"" \
    --config "target.${t}.ar=\"${ar}\""
  echo "==> cargo clippy --target ${t}"
  cargo clippy --target "${t}" \
    --config "target.${t}.linker=\"${linker}\"" \
    --config "target.${t}.ar=\"${ar}\"" \
    -- -D warnings
done

echo "android_rust_check: all targets OK (${TARGETS[*]})"
