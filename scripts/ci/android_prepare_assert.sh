#!/usr/bin/env bash
# Assert outputs of `mix mobile.prepare_release` for CI (Tier 1).
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

APP_ZIP="src-tauri/target/app-release.zip"
[[ -f "${APP_ZIP}" ]] || fail "missing ${APP_ZIP} (run BACVIEW_DESKTOP=1 mix mobile.prepare_release)"
size="$(stat -c%s "${APP_ZIP}" 2>/dev/null || stat -f%z "${APP_ZIP}")"
[[ "${size}" -gt 1024 ]] || fail "${APP_ZIP} too small (${size} bytes)"
ok "${APP_ZIP} (${size} bytes)"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
unzip -q "${APP_ZIP}" -d "${tmp}"

# Zip contains either rel/… or top-level bin/ (we zip -qry app-release.zip rel)
if [[ -d "${tmp}/rel" ]]; then
  REL="${tmp}/rel"
else
  REL="${tmp}"
fi

[[ -f "${REL}/bin/bacview" ]] || fail "app-release.zip missing bin/bacview"
[[ -f "${REL}/releases/start_erl.data" ]] || fail "app-release.zip missing releases/start_erl.data"
ok "bin/bacview and start_erl.data present"

# Host erts must be stripped before packaging
if compgen -G "${REL}/erts-*" >/dev/null; then
  fail "app-release.zip must not contain host erts-* (found under ${REL})"
fi
ok "no host erts-* in app-release.zip"

# Host NIFs must not ship
so_hits="$(find "${REL}/lib" -type f -name '*.so' 2>/dev/null | head -20 || true)"
if [[ -n "${so_hits}" ]]; then
  echo "${so_hits}" >&2
  fail "app-release.zip must not contain host .so NIFs under lib/"
fi
ok "no host .so under lib/"

if ! grep -q 'start_clean' "${REL}/bin/bacview"; then
  fail "bin/bacview missing start_clean (Android start patch)"
fi
if ! grep -q 'erlexec' "${REL}/bin/bacview"; then
  fail "bin/bacview missing erlexec (Android start patch)"
fi
if ! grep -q 'ensure_all_started' "${REL}/bin/bacview"; then
  fail "bin/bacview missing ensure_all_started (Android start patch)"
fi
ok "bin/bacview Android start patch"

# Elixir scripts under releases/* patched to erlexec
elixir_scripts="$(find "${REL}/releases" -type f -name elixir 2>/dev/null || true)"
[[ -n "${elixir_scripts}" ]] || fail "no releases/*/elixir scripts in app-release.zip"
while IFS= read -r script; do
  [[ -z "${script}" ]] && continue
  if grep -q 'ERL_EXEC="erl"' "${script}" && ! grep -q 'ERL_EXEC="erlexec"' "${script}"; then
    fail "${script} still uses ERL_EXEC=erl (expected erlexec)"
  fi
  grep -q 'ERL_EXEC="erlexec"' "${script}" ||
    fail "${script} missing ERL_EXEC=erlexec"
done <<<"${elixir_scripts}"
ok "releases/*/elixir use ERL_EXEC=erlexec"

# ERTS zips staged for Tauri resources (prepare copies or build.rs will stage later)
HOST_MAJOR="$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')"
for abi in x86_64 arm64-v8a armeabi-v7a; do
  src="priv/runtimes/android/otp${HOST_MAJOR}/erts-${abi}.zip"
  [[ -f "${src}" ]] || fail "missing source ERTS ${src}"
done
ok "source ERTS zips present for host major ${HOST_MAJOR}"

echo
echo "android_prepare_assert: all checks passed"
