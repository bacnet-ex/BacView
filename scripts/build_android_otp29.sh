#!/usr/bin/env bash
# Wrapper: cross-compile OTP 29 for Android → priv/runtimes/android/otp29/
exec "$(cd "$(dirname "$0")" && pwd)/build_android_otp.sh" 29 "$@"
