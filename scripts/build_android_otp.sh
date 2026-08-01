#!/usr/bin/env bash
# Cross-compile Erlang/OTP for Android and package erts-{abi}.zip trees
# used by BacView's process-based mobile runtime.
#
# Official docs: erlang/otp HOWTO/INSTALL-ANDROID.md
#
# Usage:
#   ./scripts/build_android_otp.sh 27                 # host-matched tag if host is OTP 27
#   ./scripts/build_android_otp.sh 28 x86_64
#   ./scripts/build_android_otp.sh 29 arm64-v8a armeabi-v7a x86_64
#   ./scripts/build_android_otp27.sh …                # thin wrappers
#
# Prerequisites: ANDROID_HOME/NDK, host OTP of the *same major* on PATH (bootstrap),
#   curl, make, perl, tar, unzip, zip, git.
#
# Env overrides:
#   OTP_TAG=OTP-28.5.0.4          # default: host OTP_VERSION when major matches, else below
#   OPENSSL_TAG=openssl-3.3.2
#   ANDROID_API=24
#   NDK_ROOT=...
#   JOBS=$(nproc)
#   WORK_DIR=_build/android_otp/otp{MAJOR}
#   OUT_DIR=priv/runtimes/android/otp{MAJOR}
#   SKIP_OPENSSL=0
#   CLEAN=0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: build_android_otp.sh <27|28|29> [abi ...]

ABIs default to: x86_64 arm64-v8a armeabi-v7a

Examples:
  ./scripts/build_android_otp.sh 27 x86_64
  ./scripts/build_android_otp28.sh
  OTP_TAG=OTP-28.5.0.4 ./scripts/build_android_otp.sh 28
EOF
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

OTP_MAJOR="$1"
shift
case "$OTP_MAJOR" in
  27 | 28 | 29) ;;
  *)
    echo "unsupported OTP major: $OTP_MAJOR (want 27, 28, or 29)" >&2
    usage
    ;;
esac

DEFAULT_ABIS=(x86_64 arm64-v8a armeabi-v7a)
if [[ $# -gt 0 ]]; then
  ABIS=("$@")
else
  ABIS=("${DEFAULT_ABIS[@]}")
fi

host_otp_release() {
  erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' 2>/dev/null || true
}

host_otp_version() {
  # e.g. 27.3.4.14 from releases/<rel>/OTP_VERSION
  erl -noshell -eval '
    Rel = erlang:system_info(otp_release),
    Path = filename:join([code:root_dir(), "releases", Rel, "OTP_VERSION"]),
    case file:read_file(Path) of
      {ok, Bin} -> io:format("~s", [string:trim(binary_to_list(Bin))]);
      _ -> io:format("~s", [Rel])
    end,
    halt().
  ' 2>/dev/null || true
}

default_otp_tag_for_major() {
  case "$1" in
    27) echo "OTP-27.3.4.15" ;;
    28) echo "OTP-28.5.0.4" ;;
    29) echo "OTP-29.0.4" ;;
  esac
}

HOST_OTP_REL="$(host_otp_release)"
HOST_OTP_VSN="$(host_otp_version)"

if [[ -z "${OTP_TAG:-}" ]]; then
  if [[ "$HOST_OTP_REL" == "$OTP_MAJOR" && -n "$HOST_OTP_VSN" && "$HOST_OTP_VSN" == *.* ]]; then
    OTP_TAG="OTP-${HOST_OTP_VSN}"
  else
    OTP_TAG="$(default_otp_tag_for_major "$OTP_MAJOR")"
  fi
fi

OPENSSL_TAG="${OPENSSL_TAG:-openssl-3.3.2}"
ANDROID_API="${ANDROID_API:-24}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
WORK_DIR="${WORK_DIR:-$ROOT/_build/android_otp/otp${OTP_MAJOR}}"
OUT_DIR="${OUT_DIR:-$ROOT/priv/runtimes/android/otp${OTP_MAJOR}}"
SKIP_OPENSSL="${SKIP_OPENSSL:-0}"
CLEAN="${CLEAN:-0}"

resolve_ndk() {
  if [[ -n "${NDK_ROOT:-}" && -d "$NDK_ROOT" ]]; then
    echo "$NDK_ROOT"
    return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "$sdk" ]]; then
    echo "Set ANDROID_HOME / ANDROID_SDK_ROOT or NDK_ROOT" >&2
    exit 1
  fi
  if [[ -d "$sdk/ndk" ]]; then
    local latest
    latest="$(ls -1 "$sdk/ndk" 2>/dev/null | sort -V | tail -1)"
    if [[ -n "$latest" ]]; then
      echo "$sdk/ndk/$latest"
      return
    fi
  fi
  if [[ -d "$sdk/ndk-bundle" ]]; then
    echo "$sdk/ndk-bundle"
    return
  fi
  echo "No NDK under $sdk" >&2
  exit 1
}

NDK_ROOT="$(resolve_ndk)"
HOST_PREBUILT="linux-x86_64"
if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ "$(uname -m)" == "arm64" ]]; then
    HOST_PREBUILT="darwin-arm64"
  else
    HOST_PREBUILT="darwin-x86_64"
  fi
fi
NDK_BIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_PREBUILT/bin"
if [[ ! -d "$NDK_BIN" ]]; then
  echo "NDK toolchain bin missing: $NDK_BIN" >&2
  exit 1
fi
export PATH="$NDK_BIN:$PATH"
export ANDROID_NDK_ROOT="$NDK_ROOT"
export NDK_ROOT
export NDK_ABI_PLAT="android${ANDROID_API}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd make
need_cmd perl
need_cmd tar
need_cmd zip
need_cmd git
need_cmd erl

if [[ "$HOST_OTP_REL" != "$OTP_MAJOR" ]]; then
  echo "WARNING: host OTP release is '${HOST_OTP_REL:-unknown}' but building major $OTP_MAJOR." >&2
  echo "  Cross-compile bootstrap should match the target OTP major. Switch host OTP or expect failures." >&2
fi

echo "==> BacView Android OTP build"
echo "    major=$OTP_MAJOR  OTP_TAG=$OTP_TAG  OPENSSL_TAG=$OPENSSL_TAG  API=$ANDROID_API"
echo "    host_otp=${HOST_OTP_VSN:-$HOST_OTP_REL}"
echo "    NDK_ROOT=$NDK_ROOT"
echo "    ABIS=${ABIS[*]}"
echo "    WORK_DIR=$WORK_DIR"
echo "    OUT_DIR=$OUT_DIR"

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR" "$OUT_DIR"

SRC_DIR="$WORK_DIR/src"
OTP_SRC="$SRC_DIR/otp"
OPENSSL_SRC="$SRC_DIR/openssl"
# OpenSSL is ABI-only — share across OTP majors under _build/android_otp/openssl
OPENSSL_SHARED="${OPENSSL_SHARED:-$ROOT/_build/android_otp/openssl}"
mkdir -p "$SRC_DIR"

fetch_otp() {
  if [[ -d "$OTP_SRC/.git" ]]; then
    echo "==> OTP source present: $OTP_SRC"
    git -C "$OTP_SRC" fetch --tags --depth 1 origin "refs/tags/$OTP_TAG:refs/tags/$OTP_TAG" 2>/dev/null || true
    git -C "$OTP_SRC" checkout -f "$OTP_TAG"
    return
  fi
  echo "==> Cloning OTP $OTP_TAG"
  git clone --depth 1 --branch "$OTP_TAG" https://github.com/erlang/otp.git "$OTP_SRC"
}

fetch_openssl() {
  if [[ -d "$OPENSSL_SRC/.git" ]]; then
    echo "==> OpenSSL source present: $OPENSSL_SRC"
    git -C "$OPENSSL_SRC" fetch --tags --depth 1 origin "refs/tags/$OPENSSL_TAG:refs/tags/$OPENSSL_TAG" 2>/dev/null || true
    git -C "$OPENSSL_SRC" checkout -f "$OPENSSL_TAG"
    return
  fi
  echo "==> Cloning OpenSSL $OPENSSL_TAG"
  git clone --depth 1 --branch "$OPENSSL_TAG" https://github.com/openssl/openssl.git "$OPENSSL_SRC"
}

abi_meta() {
  local abi="$1"
  case "$abi" in
    x86_64)
      echo "android-x86_64|erl-xcomp-x86_64-android.conf|x86_64-linux-android"
      ;;
    arm64-v8a)
      echo "android-arm64|erl-xcomp-arm64-android.conf|aarch64-linux-android"
      ;;
    armeabi-v7a)
      echo "android-arm|erl-xcomp-arm-android.conf|armv7a-linux-androideabi"
      ;;
    *)
      echo "unsupported ABI: $abi" >&2
      exit 1
      ;;
  esac
}

build_openssl() {
  local abi="$1"
  local meta openssl_target
  meta="$(abi_meta "$abi")"
  openssl_target="${meta%%|*}"

  local out="$OPENSSL_SHARED/$abi"
  if [[ -f "$out/lib/libcrypto.a" || -f "$out/lib64/libcrypto.a" ]]; then
    echo "==> OpenSSL already built for $abi ($out)"
    return
  fi

  echo "==> Building OpenSSL $OPENSSL_TAG for $abi ($openssl_target, API $ANDROID_API)"
  mkdir -p "$out"
  rm -rf "$WORK_DIR/openssl-src-$abi"
  cp -a "$OPENSSL_SRC" "$WORK_DIR/openssl-src-$abi"
  pushd "$WORK_DIR/openssl-src-$abi" >/dev/null

  ./Configure "$openssl_target" \
    -D__ANDROID_API__="$ANDROID_API" \
    no-shared \
    no-tests \
    no-ui-console \
    --prefix="$out" \
    --openssldir="$out/ssl"

  make -j"$JOBS"
  make install_sw

  if [[ -f "$out/lib64/libcrypto.a" && ! -e "$out/lib/libcrypto.a" ]]; then
    mkdir -p "$out/lib"
    ln -sfn ../lib64/libcrypto.a "$out/lib/libcrypto.a"
    [[ -f "$out/lib64/libssl.a" ]] && ln -sfn ../lib64/libssl.a "$out/lib/libssl.a"
  fi
  if [[ ! -f "$out/lib/libcrypto.a" ]]; then
    echo "OpenSSL libcrypto.a missing under $out" >&2
    exit 1
  fi

  popd >/dev/null
  echo "    OpenSSL installed: $out"
}

write_xcomp_conf() {
  local abi="$1"
  local triple="$2"
  local dest="$3"

  local cc="${triple}${ANDROID_API}-clang"
  local cxx="${triple}${ANDROID_API}-clang++"
  local ld="$cc"

  local host_triple extra_flags=""
  case "$abi" in
    x86_64) host_triple="x86_64-linux-android" ;;
    arm64-v8a) host_triple="aarch64-linux-android" ;;
    armeabi-v7a)
      host_triple="arm-linux-androideabi"
      # 32-bit Android time_t; OTP 27+ configure fails without this.
      extra_flags="--disable-year2038"
      ;;
    *)
      echo "unsupported ABI for xcomp: $abi" >&2
      exit 1
      ;;
  esac

  cat >"$dest" <<EOF
## Generated by scripts/build_android_otp.sh
## major=$OTP_MAJOR ABI=$abi OTP=$OTP_TAG API=$ANDROID_API NDK=$NDK_ROOT

erl_xcomp_build=guess
erl_xcomp_host=$host_triple
erl_xcomp_configure_flags="--without-termcap --without-wx --enable-builtin-zlib --enable-deterministic-build $extra_flags"

CC="$cc"
CXX="$cxx"
LD="$ld"
CFLAGS="-g -O2 -fPIC"
CXXFLAGS="-g -O2 -fPIC"
LDFLAGS="-static-libstdc++"
AR=llvm-ar
RANLIB=llvm-ranlib

erl_xcomp_sysroot=/sysroot/path/handled/by/the/Android/NDK
EOF
}

build_otp_abi() {
  local abi="$1"
  local meta stock_conf triple rest
  meta="$(abi_meta "$abi")"
  rest="${meta#*|}"
  stock_conf="${rest%%|*}"
  triple="${rest##*|}"

  local release_root="$WORK_DIR/release/$abi"
  local build_marker="$WORK_DIR/otp-build-$abi.done"
  if [[ -f "$build_marker" ]] && compgen -G "$release_root/erts-*" >/dev/null; then
    echo "==> OTP already released for $abi (remove $build_marker to rebuild)"
    return
  fi

  local ssl_prefix="$OPENSSL_SHARED/$abi"
  if [[ ! -f "$ssl_prefix/lib/libcrypto.a" ]]; then
    echo "OpenSSL for $abi not found at $ssl_prefix" >&2
    exit 1
  fi

  echo "==> Configuring OTP $OTP_TAG for $abi"
  local otp_tree="$WORK_DIR/otp-$abi"
  if [[ ! -d "$otp_tree/.git" && ! -f "$otp_tree/otp_build" ]]; then
    rm -rf "$otp_tree"
    cp -a "$OTP_SRC" "$otp_tree"
  fi

  local xcomp="$WORK_DIR/xcomp-$abi.conf"
  write_xcomp_conf "$abi" "$triple" "$xcomp"

  pushd "$otp_tree" >/dev/null
  export ERL_TOP="$otp_tree"
  if [[ -f Makefile ]]; then
    make clean >/dev/null 2>&1 || true
  fi

  # erl_interface is mandatory in modern OTP (cannot --without-erl_interface).
  ./otp_build configure \
    --xcomp-conf="$xcomp" \
    --with-ssl="$ssl_prefix" \
    --disable-dynamic-ssl-lib \
    --without-javac \
    --without-odbc \
    --without-wx \
    --without-observer \
    --without-debugger \
    --without-et \
    --without-megaco \
    --without-diameter \
    --without-jinterface

  echo "==> Compiling OTP for $abi (jobs=$JOBS)"
  make -j"$JOBS"

  echo "==> Releasing OTP for $abi → $release_root"
  rm -rf "$release_root"
  mkdir -p "$release_root"
  make RELEASE_ROOT="$release_root" release

  if [[ -x "$release_root/Install" ]]; then
    (cd "$release_root" && ./Install -cross -minimal /data/local/tmp/bacview-otp) || true
  fi

  if [[ -L "$release_root/bin/epmd" || -e "$release_root/bin/epmd" ]]; then
    local erts_epmd
    erts_epmd="$(find "$release_root" -path '*/erts-*/bin/epmd' -type f | head -1)"
    if [[ -n "$erts_epmd" ]]; then
      rm -f "$release_root/bin/epmd"
      cp "$erts_epmd" "$release_root/bin/epmd"
    fi
  fi

  popd >/dev/null
  touch "$build_marker"
  echo "    Release ready: $release_root"
}

package_zip() {
  local abi="$1"
  local release_root="$WORK_DIR/release/$abi"
  local zip_path="$OUT_DIR/erts-$abi.zip"
  local stage="$WORK_DIR/stage-$abi"

  if [[ ! -d "$release_root" ]]; then
    echo "no release for $abi at $release_root" >&2
    exit 1
  fi

  echo "==> Packaging $zip_path"
  rm -rf "$stage"
  mkdir -p "$stage"
  cp -a "$release_root"/. "$stage"/

  find "$stage" -type d \( -name include -o -name c_src -o -name src -o -name doc -o -name man -o -name examples \) -prune -exec rm -rf {} + 2>/dev/null || true
  find "$stage" -type f \( -name '*.a' -o -name '*.o' -o -name '*.gz' -o -name '*.pdf' -o -name '*.html' \) -delete 2>/dev/null || true

  local beam
  beam="$(find "$stage" -path '*/erts-*/bin/beam.smp' -type f | head -1)"
  if [[ -z "$beam" ]]; then
    echo "beam.smp missing in release for $abi" >&2
    exit 1
  fi
  for helper in erlexec erl_child_setup; do
    if ! find "$stage" -path "*/erts-*/bin/$helper" -type f | grep -q .; then
      echo "missing erts helper: $helper" >&2
      exit 1
    fi
  done

  if command -v llvm-strip >/dev/null 2>&1; then
    find "$stage" -type f -perm -111 \( -name 'beam.smp' -o -name 'erlexec' -o -name 'erl_child_setup' -o -name 'inet_gethost' -o -name 'epmd' -o -name '*.so' \) \
      -exec llvm-strip --strip-unneeded {} + 2>/dev/null || true
  fi

  rm -f "$zip_path"
  (cd "$stage" && zip -qr "$zip_path" .)
  local sz
  sz="$(du -h "$zip_path" | awk '{print $1}')"
  echo "    Wrote $zip_path ($sz)"
}

# --- main ---
fetch_otp
if [[ "$SKIP_OPENSSL" != "1" ]]; then
  fetch_openssl
fi

for abi in "${ABIS[@]}"; do
  echo
  echo "######## ABI $abi ########"
  if [[ "$SKIP_OPENSSL" != "1" ]]; then
    build_openssl "$abi"
  fi
  build_otp_abi "$abi"
  package_zip "$abi"
done

echo
echo "==> Done. Host-matched trees for mobile.prepare_release:"
ls -lh "$OUT_DIR"/erts-*.zip 2>/dev/null || true
echo
echo "Rebuild APK (host OTP major must be $OTP_MAJOR):"
echo "  BACVIEW_DESKTOP=1 mix mobile.android.build"
