#!/usr/bin/env bash
set -euo pipefail

# Build Mix release + Android APK/AAB via Tauri.
# Requires: Android SDK/NDK, JAVA_HOME, rust Android targets, BACVIEW_DESKTOP=1.

export MIX_ENV=prod
export BACVIEW_DESKTOP=1
export BACVIEW_ENABLE_MSTP=0

if [[ -z "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]]; then
  echo "ANDROID_HOME or ANDROID_SDK_ROOT must point at the Android SDK." >&2
  exit 1
fi

mix mobile.android.build
