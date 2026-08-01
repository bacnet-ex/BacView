#!/usr/bin/env bash
# Install (or reuse cached) Android SDK platform-tools, build-tools, platform, and NDK.
# Used by GitLab Android CI jobs. Safe to re-run.
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${CI_PROJECT_DIR:-.}/.android-sdk}}"
export ANDROID_SDK_ROOT
export ANDROID_HOME="${ANDROID_SDK_ROOT}"

# Keep versions aligned with gen/android (compileSdk 36, minSdk 24).
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-36}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
# Side-by-side NDK; override with ANDROID_NDK_VERSION if needed.
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-27.2.12479018}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-11076708}"

mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
TOOLS_DIR="${ANDROID_SDK_ROOT}/cmdline-tools/latest"

if [[ ! -x "${TOOLS_DIR}/bin/sdkmanager" ]]; then
  echo "Installing Android command-line tools…"
  tmp="$(mktemp -d)"
  archive="commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
  url="https://dl.google.com/android/repository/${archive}"
  curl -fsSL -o "${tmp}/${archive}" "${url}"
  unzip -q "${tmp}/${archive}" -d "${tmp}"
  rm -rf "${TOOLS_DIR}"
  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
  mv "${tmp}/cmdline-tools" "${TOOLS_DIR}"
  rm -rf "${tmp}"
fi

export PATH="${TOOLS_DIR}/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"

yes 2>/dev/null | sdkmanager --licenses >/dev/null || true

packages=(
  "platform-tools"
  "platforms;${ANDROID_PLATFORM}"
  "build-tools;${ANDROID_BUILD_TOOLS}"
  "ndk;${ANDROID_NDK_VERSION}"
)

# Emulator extras only when requested (Tier 2).
if [[ "${ANDROID_INSTALL_EMULATOR:-0}" == "1" ]]; then
  packages+=(
    "emulator"
    "system-images;android-30;google_apis;x86_64"
  )
fi

echo "sdkmanager: ${packages[*]}"
sdkmanager --install "${packages[@]}"

NDK_DIR="${ANDROID_SDK_ROOT}/ndk/${ANDROID_NDK_VERSION}"
if [[ ! -d "${NDK_DIR}" ]]; then
  # Fall back to any installed NDK
  NDK_DIR="$(find "${ANDROID_SDK_ROOT}/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1 || true)"
fi
[[ -d "${NDK_DIR}" ]] || {
  echo "ERROR: NDK not found under ${ANDROID_SDK_ROOT}/ndk" >&2
  exit 1
}

export ANDROID_NDK_HOME="${NDK_DIR}"
export ANDROID_NDK_ROOT="${NDK_DIR}"

# Write env file for subsequent script steps (source it).
ENV_FILE="${ANDROID_SDK_ENV_FILE:-${ANDROID_SDK_ROOT}/ci-env.sh}"
cat >"${ENV_FILE}" <<EOF
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}"
export ANDROID_HOME="${ANDROID_SDK_ROOT}"
export ANDROID_NDK_HOME="${NDK_DIR}"
export ANDROID_NDK_ROOT="${NDK_DIR}"
export PATH="${TOOLS_DIR}/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_SDK_ROOT}/emulator:\${PATH}"
EOF

echo "Android SDK ready at ${ANDROID_SDK_ROOT}"
echo "NDK: ${NDK_DIR}"
echo "Env file: ${ENV_FILE}"
