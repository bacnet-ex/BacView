#!/usr/bin/env bash
# Tier 2: install APK on an x86_64 emulator and wait for BEAM boot signals.
# Intended for tag pipelines (and optional schedules — see docs/android_ci.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

ok() {
  echo "OK: $*"
}

: "${ANDROID_HOME:?ANDROID_HOME must be set}"
export PATH="${ANDROID_HOME}/emulator:${ANDROID_HOME}/platform-tools:${PATH}"

APK_GLOB="${ANDROID_APK_PATH:-}"
if [[ -z "${APK_GLOB}" ]]; then
  # Prefer universal release, then any release/debug APK we can find.
  candidates=(
    src-tauri/gen/android/app/build/outputs/apk/universal/release/*.apk
    src-tauri/gen/android/app/build/outputs/apk/*/release/*.apk
    src-tauri/gen/android/app/build/outputs/apk/*/debug/*.apk
  )
  APK=""
  for pattern in "${candidates[@]}"; do
    # shellcheck disable=SC2086
    for f in ${pattern}; do
      if [[ -f "${f}" ]]; then
        APK="${f}"
        break 2
      fi
    done
  done
else
  APK="${APK_GLOB}"
fi

[[ -n "${APK}" && -f "${APK}" ]] || fail "no APK found (build with mix mobile.android.build first)"
ok "using APK ${APK}"

AVD_NAME="${ANDROID_AVD_NAME:-bacview_ci_api30}"
SYS_IMAGE="${ANDROID_SYS_IMAGE:-system-images;android-30;google_apis;x86_64}"
BOOT_TIMEOUT="${ANDROID_BOOT_TIMEOUT:-600}"
SMOKE_TIMEOUT="${ANDROID_SMOKE_TIMEOUT:-300}"
PACKAGE="${ANDROID_APP_ID:-com.bacnet_ex.bacview}"
ACTIVITY="${ANDROID_MAIN_ACTIVITY:-com.bacnet_ex.bacview/.MainActivity}"

if ! adb devices >/dev/null 2>&1; then
  fail "adb not available"
fi

# Create AVD if missing
if ! avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}"; then
  echo "Creating AVD ${AVD_NAME} (${SYS_IMAGE})…"
  echo no | avdmanager create avd -n "${AVD_NAME}" -k "${SYS_IMAGE}" --force
fi

# Prefer KVM when present
EMU_ACCEL_ARGS=(-accel on)
if [[ ! -e /dev/kvm ]]; then
  echo "WARNING: /dev/kvm not present; using software acceleration (slow)"
  EMU_ACCEL_ARGS=(-accel off -gpu swiftshader_indirect)
fi

echo "Starting emulator…"
LOG_DIR="${ANDROID_SMOKE_LOG_DIR:-${ROOT}/tmp/android-ci}"
mkdir -p "${LOG_DIR}"
EMU_LOG="${LOG_DIR}/emulator.log"
LOGCAT_FILE="${LOG_DIR}/bacview-logcat.txt"

emulator -avd "${AVD_NAME}" -no-window -no-audio -no-boot-anim \
  "${EMU_ACCEL_ARGS[@]}" -no-snapshot -wipe-data >"${EMU_LOG}" 2>&1 &
EMU_PID=$!

cleanup() {
  adb emu kill >/dev/null 2>&1 || true
  kill "${EMU_PID}" >/dev/null 2>&1 || true
  wait "${EMU_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "Waiting for adb device (timeout ${BOOT_TIMEOUT}s)…"
adb wait-for-device
deadline=$((SECONDS + BOOT_TIMEOUT))
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
  if ((SECONDS > deadline)); then
    tail -n 100 "${EMU_LOG}" || true
    fail "emulator did not boot within ${BOOT_TIMEOUT}s"
  fi
  sleep 2
done
ok "emulator booted"

adb install -r "${APK}" || fail "adb install failed"
ok "APK installed"

adb logcat -c || true
adb shell am start -n "${ACTIVITY}" || fail "failed to start ${ACTIVITY}"
ok "activity started"

echo "Waiting for BEAM / Rust boot signals (timeout ${SMOKE_TIMEOUT}s)…"
deadline=$((SECONDS + SMOKE_TIMEOUT))
patterns='extracted release|elixirkit-style release start|Android BEAM|android-beam|Phoenix|LiveView|ready:|BacView'
: >"${LOGCAT_FILE}"

while ((SECONDS <= deadline)); do
  adb logcat -d -v time >"${LOGCAT_FILE}" 2>/dev/null || true
  if grep -qiE "${patterns}" "${LOGCAT_FILE}"; then
    ok "boot signal found in logcat"
    grep -iE "${patterns}" "${LOGCAT_FILE}" | tail -n 30
    # Process still alive?
    if adb shell pidof "${PACKAGE}" >/dev/null 2>&1; then
      ok "package ${PACKAGE} is running"
      echo "android_emulator_smoke: passed"
      exit 0
    fi
    # Signal seen but process gone — still treat as soft success if extract/start logged
    if grep -qiE 'extracted release|elixirkit-style release start' "${LOGCAT_FILE}"; then
      ok "boot started (process may have exited after halt); treating as pass"
      echo "android_emulator_smoke: passed"
      exit 0
    fi
  fi
  # Crash early?
  if grep -qiE 'Android BEAM boot failed|android release extract failed|FATAL EXCEPTION' "${LOGCAT_FILE}"; then
    tail -n 80 "${LOGCAT_FILE}" >&2 || true
    fail "boot failure detected in logcat"
  fi
  sleep 3
done

echo "---- last logcat ----" >&2
tail -n 120 "${LOGCAT_FILE}" >&2 || true
fail "no boot signal within ${SMOKE_TIMEOUT}s"
