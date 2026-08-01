# Android CI

How BacView validates the experimental Android (Tauri + process-based BEAM) app
in GitLab CI, and how to extend it.

## Pipeline overview

| Tier | Job(s) | When | What |
|------|--------|------|------|
| **0** | `android-static` | Android-related path changes only | ERTS zip integrity, OTP **major** match, manifest, Tauri resources, Gradle W^X/cleartext |
| **1** | `android-rust` | Android-related path changes only | `cargo check` + `clippy` for `aarch64-linux-android` and `x86_64-linux-android` |
| **1** | `android-package` | Android-related path changes only | `BACVIEW_DESKTOP=1 mix mobile.prepare_release`, structural zip asserts, `mix mobile.android.build` (debug-key OK) |
| **2** | `android-emulator` | **Tags** with Android path changes (+ schedule / force) | Install APK on x86_64 AVD, wait for Rust/BEAM boot log signals |
| **3** | — | *Not implemented* | See [Future: Tier 3](#future-tier-3) |

### Path filters (Tier 0+1)

Android jobs **do not** run on ordinary Elixir/LiveView changes. They run when any of
these change (see `.android-change-paths` in `.gitlab-ci.yml`):

- `src-tauri/**/*` (Rust shell, Tauri, Gradle under `gen/android`)
- `priv/runtimes/android/**/*`
- `scripts/ci/android*`, `scripts/*android*`, `scripts/build_android*`, `scripts/mobile_android*`
- `lib/bac_view/mobile/**/*` (mobile/Android Elixir helpers only)
- `.gitlab-ci.yml`

Skip all Android jobs: set `GITLAB_CI_SKIP_ANDROID=1` (or `GITLAB_CI_SKIP_BUILD=1`).

Force Android jobs when path rules would skip them: `FORCE_GITLAB_CI=1` or
`FORCE_ANDROID_E2E=1`. Schedule smoke (`ANDROID_EMULATOR_SMOKE=1`) also forces
Tier 0+1 so the APK exists for the emulator job.

## Local equivalents

```bash
# Tier 0
./scripts/ci/android_static_check.sh

# Tier 1 — Rust targets (needs NDK)
export ANDROID_HOME=…   # or run scripts/ci/android_setup_sdk.sh
source "${ANDROID_HOME}/ci-env.sh"   # written by android_setup_sdk.sh in CI
./scripts/ci/android_rust_check.sh

# Tier 1 — prepare + assert + APK
export ANDROID_HOME=…
export BACVIEW_DESKTOP=1 MIX_ENV=prod
mix mobile.prepare_release
./scripts/ci/android_prepare_assert.sh
mix mobile.android.build

# Tier 2 — emulator smoke (needs KVM preferred, APK already built)
ANDROID_INSTALL_EMULATOR=1 ./scripts/ci/android_setup_sdk.sh
source "${ANDROID_HOME}/ci-env.sh"
./scripts/ci/android_emulator_smoke.sh
```

## OTP major matching

Host OTP and `priv/runtimes/android/otp{N}/` must share the same **major**
(e.g. host `27.2.4` with zip `27.3.4.14` is fine). Exact patch equality is
**not** required; see `BacView.Mobile.AndroidErts` and
`mix mobile.prepare_release` (`ensure_host_matched_android_erts`).

On device, `android_runtime` rewrites `releases/start_erl.data` and release
script `ERTS_BIN` to the Android ERTS version.

## Scripts

| Script | Role |
|--------|------|
| `scripts/ci/android_static_check.sh` | Tier 0 |
| `scripts/ci/android_setup_sdk.sh` | SDK/NDK (and optional emulator image) install for CI |
| `scripts/ci/android_rust_check.sh` | Tier 1 Android Rust targets |
| `scripts/ci/android_prepare_assert.sh` | Assert `app-release.zip` after prepare |
| `scripts/ci/android_emulator_smoke.sh` | Tier 2 AVD install + logcat boot wait |

## Emulator job requirements

- Docker executor with **KVM** (`/dev/kvm`) strongly recommended; software
  acceleration works but is slow and flaky.
- Tag the job/runner if you use dedicated hardware: e.g. `tags: [kvm]` in
  `.gitlab-ci.yml` (adjust to your runner labels).
- Artifacts from `android-package` supply the APK.

### Running emulator smoke on a schedule

Tier 2 is wired for **git tags** by default. To run the same smoke on a
**scheduled pipeline** without tagging:

1. In GitLab: **CI/CD → Schedules → New schedule** (e.g. weekly on `main` / `android`).
2. Add variable **`ANDROID_EMULATOR_SMOKE=1`** (or set **`FORCE_ANDROID_E2E=1`**).
3. Ensure the schedule uses a runner that can start an emulator (KVM if possible).
4. The schedule will still run Tier 0+1 jobs for that ref; `android-emulator`
   additionally starts when:
   - `CI_PIPELINE_SOURCE == "schedule"` **and** `ANDROID_EMULATOR_SMOKE=1`, or
   - `FORCE_ANDROID_E2E=1` on any pipeline, or
   - `CI_COMMIT_TAG` is set.

Example schedule variables:

```text
ANDROID_EMULATOR_SMOKE=1
# optional: longer waits
# ANDROID_BOOT_TIMEOUT=900
# ANDROID_SMOKE_TIMEOUT=600
```

## Signing in CI

Release builds fall back to the Android **debug** keystore when
`BACVIEW_ANDROID_*` / `keystore.properties` are absent (fine for install/smoke).

For Play-oriented artifacts on tags, set CI/CD variables (masked):

- `BACVIEW_ANDROID_STORE_FILE` (path or file variable)
- `BACVIEW_ANDROID_STORE_PASSWORD`
- `BACVIEW_ANDROID_KEY_ALIAS`
- `BACVIEW_ANDROID_KEY_PASSWORD`

Never commit `keystore.properties` or `.jks` files.

## Caching

Jobs cache under the project directory where practical:

- `.android-sdk` — SDK/NDK (large; first run slow)
- `.cargo` / `.rustup` — Rust toolchains and Android targets
- `src-tauri/target` — Cargo build artifacts
- Mix `_build` / `deps` for desktop/mobile prepare

## Future: Tier 3

Not implemented in the current pipeline. When you need them, extend
`.gitlab-ci.yml` and this doc:

| Extension | Purpose | Notes |
|-----------|---------|--------|
| **OTP rebuild job** | Nightly/manual `scripts/build_android_otp.sh {major} x86_64` | Multi-hour; cache `_build/android_otp`; validate script + NDK still produce good zips; optional artifact or commit bot |
| **Multi-ABI release matrix** | Tag builds for arm64 + x86_64 (armeabi-v7a optional) | Separate from universal APK; attach as release assets |
| **Signed AAB upload path** | Tag job with real keystore secrets → `.aab` | Store signing secrets in GitLab; never debug-key for store |
| **OTP major matrix** | Host images 27 / 28 / 29 with matching `otp{N}/` zips | Only when multiple majors are shipped in-tree |

Suggested rules for a future nightly OTP rebuild (sketch only):

```yaml
# NOT active — Tier 3 sketch
# android-otp-rebuild:
#   stage: build
#   rules:
#     - if: '$CI_PIPELINE_SOURCE == "schedule" && $ANDROID_OTP_REBUILD == "1"'
#     - if: '$FORCE_ANDROID_OTP_REBUILD == "1"'
#   script:
#     - ./scripts/build_android_otp.sh 27 x86_64
#     - ./scripts/ci/android_static_check.sh
```

Prefer verifying **committed** ERTS zips (Tier 0) on every commit over rebuilding
OTP on every pipeline.

## Related code

- `mix.exs` — `mobile.prepare_release` / `mobile.android.*`
- `lib/bac_view/mobile/android_erts.ex` — OTP major helper
- `src-tauri/src/android_runtime.rs` — extract/merge ERTS
- `src-tauri/src/android_beam.rs` — process boot
- `src-tauri/build.rs` — stage ERTS zips + jniLibs helpers
- `src-tauri/gen/android/` — Gradle project
