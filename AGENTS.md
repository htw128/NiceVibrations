# AGENTS.md

## Quick commands

```bash
cargo fmt -- --check          # formatting (also pre-commit hook)
cargo clippy --all-targets -- -D warnings  # lint (warnings are errors)
cargo build                    # build all Rust crates
cargo build --benches          # verify benchmarks compile
cargo test                     # run all Rust tests
./ci-rust-core.sh              # full Rust CI: fmt → clippy → build → build-benches → test
```

Run the full `ci-rust-core.sh` pipeline locally before pushing — the same script runs in CI and as the `pre-push` hook.

## Architecture

This is a Cargo workspace (Rust 1.60.0) with 6 members. The layered dependency graph:

```
Unity C# asset (interfaces/unity)
  ├── Android → interfaces/android (Java/JNI) → core/api (JNI bindings)
  ├── iOS     → interfaces/ios (Obj-C/C)       → core/api (C bindings)
  └── Editor  → unity-editor-plugin (Rust)     → core/datamodel
                       │
core/api ──→ core/lib ──→ core/datamodel + clip-players
```

## Workspace member gotchas

- `core/utils` is **not** a workspace member. It is a path dependency used by `datamodel` and `clip-players`. Running `cargo test` from the root will not run its tests.
- `core/api` exports as `lofelt_sdk` (library name ≠ directory name). Its `build.rs` uses cbindgen to generate `core/api/lofelt-sdk.h` — this file is `.gitignore`d. If you change public C API types, rebuilt it and check the generated header.
- `unity-editor-plugin` on macOS builds a **universal binary** (arm64 + x86_64) via `lipo`. Its tests run only the host architecture. Use its own `build-shared-library.sh`, not plain `cargo build`.

## Git hooks

Managed by `rusty-hook` (config in `.rusty-hook.toml`):
- **pre-commit**: `cargo fmt -- --check`
- **pre-push**: `./ci-rust-core.sh`

First-time setup: `cargo install rusty-hook && rusty-hook init`

## Platform builds (macOS host)

Each requires its own setup (Xcode/NDK/JDK) — see the respective READMEs:
```bash
./build-platform.sh ios
./build-platform.sh android
./build-platform.sh unity-editor-plugin-host
```

The full asset build (`./build.sh`) runs all three sequentially plus docs generation.

## CI notes

- `ci-rust-core.sh` runs on push to any branch (Windows + Linux matrix).
- `ci-ios.sh`, `ci-android.sh`, `ci-unity-editor-plugin.sh` run only on merge to `main`.
- `ci-unity.sh` (Unity playmode tests with Unity 2019.4.16f1) **never runs in GHA** — it requires a Unity license. Run locally before releasing.
- Release tags follow the pattern `sdk-X.Y.Z-nicevibrations-A.B.C` or `haptic2ahap-X.Y.Z`.

## Rust conventions

- No `rustfmt.toml` — stock rustfmt defaults.
- Clippy treats warnings as errors (`-D warnings`). If a clippy lint fires, fix it or the CI will fail.
- `cargo build --benches` must succeed even if no benchmarks are actually run. This step catches broken bench code.
- iOS Rust builds can get into a broken state after switching Xcode versions; run `./clean-ios-rust.sh` to recover.

## Android build: downgrade to compileSdk 35 + AGP 7.4.2

When building the Android AAR for Unity (which requires AGP 7.4.2 and compileSdk ≤35), the following
environment is required:

```bash
export JAVA_HOME="/Users/oliver/Library/Android/OpenJDK/jdk-17.0.18+8/Contents/Home"  # JDK 17 (not 25)
```

### Required SDK packages

```
sdkmanager "platforms;android-35"
sdkmanager "build-tools;35.0.0"
```

### Code changes from the default compileSdk 36 / AGP 9.0.1 setup

1. **`build.gradle`** (root): AGP `9.0.1` → `7.4.2`
2. **`LofeltHaptics/build.gradle`**: `compileSdk 35`, add `buildToolsVersion "35.0.0"`
3. **`gradle/wrapper/gradle-wrapper.properties`**: Gradle `9.1.0` → `7.6.3`

### Known issue: aapt2 / android-35 incompatibility

AGP 7.4.2 bundles aapt2 2.19-8841542 which cannot parse `platforms;android-35`'s `android.jar`
— it fails with `RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data`.

**Fix**: Replace the AGP-cached aapt2 with the build-tools 35.0.0 version (same major version, compatible build):

```bash
cp $ANDROID_HOME/build-tools/35.0.0/aapt2 \
   ~/.gradle/caches/transforms-3/*/transformed/aapt2-7.4.2-*-osx/aapt2
```

### Known issue: `android:pageSizeCompat` attribute

`android:pageSizeCompat="enabled"` was added in AndroidManifest.xml for compileSdk 36 / extension SDK 15.
It is **not** available in the base `platforms;android-35` package. Remove it (or install `platforms;android-35-ext15`).

```xml
<!-- Before -->
<application android:pageSizeCompat="enabled" />

<!-- After (android-35 base) -->
<application />
```
