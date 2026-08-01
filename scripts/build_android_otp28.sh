#!/usr/bin/env bash
# Wrapper: cross-compile OTP 28 for Android → priv/runtimes/android/otp28/
exec "$(cd "$(dirname "$0")" && pwd)/build_android_otp.sh" 28 "$@"
