#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
set -e

export ANDROID_HOME="${ANDROID_HOME:-/Users/oliver/Library/Android/sdk/}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/Users/oliver/Library/Android/sdk/ndk/27.3.13750724/}"
export JAVA_HOME="/Users/oliver/Library/Android/OpenJDK/jdk-17.0.18+8/Contents/Home"

WORKSPACE_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
API_DIR="$WORKSPACE_ROOT/core/api"
TARGET_DIR="$WORKSPACE_ROOT/target"
JNILIBS_DIR="LofeltHaptics/src/main/jniLibs"
AAR_PATH="LofeltHaptics/build/outputs/aar/LofeltHaptics-release.aar"
NDK_READELF="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"

exit_with_failure() {
    echo "❌ $*" 1>&2 ; exit 1;
}

echo "==========================================="
echo "Cleaning"
echo "==========================================="
./gradlew clean || exit_with_failure "Failed to clean the build"
rm -rf javadoc/ "$JNILIBS_DIR"

echo "==========================================="
echo "Building Rust native libraries (16KB aligned via .cargo/config.toml)"
echo "==========================================="

cargo ndk \
    --manifest-path "$API_DIR/Cargo.toml" \
    --platform 26 \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86 \
    -t x86_64 \
    -o "$JNILIBS_DIR" \
    -- build --release --target-dir "$TARGET_DIR" \
    || exit_with_failure "cargo ndk build failed"

echo "==========================================="
echo "Assembling AAR"
echo "==========================================="
./gradlew assembleRelease || exit_with_failure "Failed to build the AAR"

echo "==========================================="
echo "Verifying AAR"
echo "==========================================="

AAR_FILE_SIZE=$(wc -c < "$AAR_PATH")
if (( AAR_FILE_SIZE < 400000 )); then
    exit_with_failure "AAR file seems to be missing the JNI libraries (size: $AAR_FILE_SIZE bytes)"
fi
echo "  → AAR size: $AAR_FILE_SIZE bytes ✓"

echo "==========================================="
echo "Verifying 16KB ELF segment alignment"
echo "==========================================="

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
    so_file="$JNILIBS_DIR/$abi/liblofelt_sdk.so"
    echo "  → $abi:"
    "$NDK_READELF" -l "$so_file" 2>/dev/null | grep "LOAD" | while read -r line; do
        echo "      $line"
    done
done

echo ""
echo "✅ AAR built successfully with 16KB-aligned native libraries!"
echo "   $AAR_PATH"

echo "==========================================="
echo "API Documentation"
echo "==========================================="
./gradlew generateJavadoc || exit_with_failure "Failed to build API documentation"
