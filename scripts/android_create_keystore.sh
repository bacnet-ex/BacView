#!/usr/bin/env bash
# Create a local Android release keystore + keystore.properties for BacView.
# For Play Store / production, keep this keystore backed up offline — losing it
# means you cannot update the same applicationId.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/src-tauri/gen/android"
KEYSTORE="$ANDROID_DIR/bacview-release.jks"
PROPS="$ANDROID_DIR/keystore.properties"
ALIAS="${BACVIEW_ANDROID_KEY_ALIAS:-bacview}"
VALIDITY_DAYS="${BACVIEW_ANDROID_KEY_VALIDITY_DAYS:-10000}"

if [[ ! -d "$ANDROID_DIR" ]]; then
  echo "Missing $ANDROID_DIR — run cargo tauri android init first." >&2
  exit 1
fi

if [[ -f "$KEYSTORE" ]]; then
  echo "Keystore already exists: $KEYSTORE" >&2
  echo "Remove it first if you intend to rotate the key." >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found (install a JDK)." >&2
  exit 1
fi

read -r -s -p "Keystore / key password: " STORE_PASS
echo
if [[ -z "$STORE_PASS" ]]; then
  echo "Password must not be empty." >&2
  exit 1
fi
read -r -s -p "Confirm password: " STORE_PASS2
echo
if [[ "$STORE_PASS" != "$STORE_PASS2" ]]; then
  echo "Passwords do not match." >&2
  exit 1
fi

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE" \
  -storetype JKS \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=BacView, OU=Mobile, O=bacnet-ex, L=Unknown, ST=Unknown, C=CH"

umask 077
cat >"$PROPS" <<EOF
storeFile=bacview-release.jks
storePassword=$STORE_PASS
keyAlias=$ALIAS
keyPassword=$STORE_PASS
EOF

echo
echo "Created:"
echo "  $KEYSTORE"
echo "  $PROPS"
echo
echo "Both are gitignored. Rebuild with:"
echo "  BACVIEW_DESKTOP=1 mix mobile.android.build"
echo
echo "Installable release APK (after build):"
echo "  src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk"
