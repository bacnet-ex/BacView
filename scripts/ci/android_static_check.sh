#!/usr/bin/env bash
# Tier 0: static integrity checks for the Android app packaging surface.
# No Android SDK, NDK, or emulator required.
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

HOST_MAJOR="$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null || true)"
if [[ -z "${HOST_MAJOR}" ]]; then
  fail "could not detect host OTP major (is erl on PATH?)"
fi
ok "host OTP major=${HOST_MAJOR}"

ERTS_DIR="priv/runtimes/android/otp${HOST_MAJOR}"
ABIS=(x86_64 arm64-v8a armeabi-v7a)
declare -A ZIP_OTP_VERSIONS=()

[[ -d "${ERTS_DIR}" ]] || fail "missing ${ERTS_DIR} (build with ./scripts/build_android_otp.sh ${HOST_MAJOR})"

for abi in "${ABIS[@]}"; do
  zip="${ERTS_DIR}/erts-${abi}.zip"
  [[ -f "${zip}" ]] || fail "missing ${zip}"
  size="$(stat -c%s "${zip}" 2>/dev/null || stat -f%z "${zip}")"
  [[ "${size}" -gt 1024 ]] || fail "${zip} is empty/placeholder (${size} bytes)"

  unzip -tqq "${zip}" >/dev/null || fail "unzip -t failed for ${zip}"

  listing="$(unzip -Z1 "${zip}")"
  # Use here-strings (not pipes): with pipefail, `echo | grep -q` can fail via SIGPIPE
  # when grep exits early after a match.
  grep -q 'OTP_VERSION' <<<"${listing}" || fail "${zip}: no OTP_VERSION member"
  grep -qE 'erts-[^/]+/bin/beam\.smp' <<<"${listing}" || fail "${zip}: missing erts-*/bin/beam.smp"
  grep -qE 'erts-[^/]+/bin/erlexec' <<<"${listing}" || fail "${zip}: missing erts-*/bin/erlexec"
  grep -qE 'erts-[^/]+/bin/erl_child_setup' <<<"${listing}" || fail "${zip}: missing erts-*/bin/erl_child_setup"

  otp_member="$(grep 'OTP_VERSION$' <<<"${listing}" | head -1)"
  otp_ver="$(unzip -p "${zip}" "${otp_member}" | tr -d '[:space:]')"
  [[ -n "${otp_ver}" ]] || fail "${zip}: empty OTP_VERSION"
  zip_major="${otp_ver%%.*}"
  [[ "${zip_major}" == "${HOST_MAJOR}" ]] ||
    fail "${zip}: OTP_VERSION=${otp_ver} major ${zip_major} != host major ${HOST_MAJOR}"

  ZIP_OTP_VERSIONS["${abi}"]="${otp_ver}"
  ok "${zip} (${size} bytes, OTP ${otp_ver})"
done

# All ABIs should come from the same OTP build (full version string).
first_ver="${ZIP_OTP_VERSIONS[${ABIS[0]}]}"
for abi in "${ABIS[@]}"; do
  [[ "${ZIP_OTP_VERSIONS[${abi}]}" == "${first_ver}" ]] ||
    fail "OTP_VERSION mismatch across ABIs: ${ABIS[0]}=${first_ver} ${abi}=${ZIP_OTP_VERSIONS[${abi}]}"
done
ok "all ABIs share OTP_VERSION=${first_ver}"

# Optional ELF machine checks when file/readelf available
if command -v file >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT
  for abi in "${ABIS[@]}"; do
    zip="${ERTS_DIR}/erts-${abi}.zip"
    beam_member="$(unzip -Z1 "${zip}" | grep -E 'erts-[^/]+/bin/beam\.smp$' | head -1)"
    unzip -p "${zip}" "${beam_member}" >"${tmp}/beam.smp"
    desc="$(file -b "${tmp}/beam.smp" || true)"
    # Soft check: warn on unexpected arch; hard-fail only if clearly wrong peer ABI
    case "${abi}" in
      x86_64)
        echo "${desc}" | grep -qiE 'x86-64|x86_64|Intel 80386|AMD' ||
          fail "erts-x86_64 beam.smp does not look like x86_64: ${desc}"
        ;;
      arm64-v8a)
        echo "${desc}" | grep -qiE 'aarch64|ARM aarch64|ARM64' ||
          fail "erts-arm64-v8a beam.smp does not look like aarch64: ${desc}"
        ;;
      armeabi-v7a)
        # 32-bit ARM; must not be x86_64 or aarch64
        echo "${desc}" | grep -qiE 'x86-64|x86_64|aarch64|ARM aarch64' &&
          fail "erts-armeabi-v7a beam.smp looks like wrong arch: ${desc}"
        echo "${desc}" | grep -qiE 'ARM|arm|ELF' ||
          fail "erts-armeabi-v7a beam.smp unexpected: ${desc}"
        ;;
    esac
    ok "beam.smp ${abi}: ${desc}"
  done
fi

MANIFEST="src-tauri/gen/android/app/src/main/AndroidManifest.xml"
[[ -f "${MANIFEST}" ]] || fail "missing ${MANIFEST}"
grep -q 'android.permission.INTERNET' "${MANIFEST}" || fail "AndroidManifest missing INTERNET"
grep -q 'android.permission.ACCESS_NETWORK_STATE' "${MANIFEST}" ||
  fail "AndroidManifest missing ACCESS_NETWORK_STATE"
ok "AndroidManifest network permissions"

TAURI_CONF="src-tauri/tauri.conf.json"
[[ -f "${TAURI_CONF}" ]] || fail "missing ${TAURI_CONF}"
for res in app-release.zip erts-x86_64.zip erts-arm64-v8a.zip erts-armeabi-v7a.zip; do
  grep -q "${res}" "${TAURI_CONF}" || fail "tauri.conf.json missing resource ${res}"
done
ok "tauri.conf.json bundle resources"

GRADLE="src-tauri/gen/android/app/build.gradle.kts"
[[ -f "${GRADLE}" ]] || fail "missing ${GRADLE}"
grep -q 'minSdk' "${GRADLE}" || fail "build.gradle.kts missing minSdk"
grep -q 'useLegacyPackaging' "${GRADLE}" ||
  fail "build.gradle.kts missing useLegacyPackaging (required for W^X jniLibs)"
grep -q 'usesCleartextTraffic' "${GRADLE}" ||
  fail "build.gradle.kts missing usesCleartextTraffic (Phoenix WebView)"
ok "Gradle packaging / cleartext settings"

[[ -f "src-tauri/gen/android/keystore.properties.example" ]] ||
  fail "missing keystore.properties.example"
if [[ -f "src-tauri/gen/android/keystore.properties" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git ls-files --error-unmatch src-tauri/gen/android/keystore.properties >/dev/null 2>&1; then
      fail "keystore.properties must not be tracked by git"
    fi
  fi
fi
ok "keystore.properties not tracked; example present"

echo
echo "android_static_check: all checks passed"
