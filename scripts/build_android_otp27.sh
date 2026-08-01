#!/usr/bin/env bash
# Wrapper: cross-compile OTP 27 for Android → priv/runtimes/android/otp27/
exec "$(cd "$(dirname "$0")" && pwd)/build_android_otp.sh" 27 "$@"
