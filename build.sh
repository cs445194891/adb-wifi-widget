#!/bin/bash
# build.sh -- bootstrap a minimal Android build env (if needed) and build the widget APK.
# Tested on macOS (Apple Silicon / Intel). Linux needs minor JDK/SDK URL swaps.
#
# What it does:
#   1. Ensure JDK 17, Android SDK cmdline-tools, platform 34, build-tools 34.0.0.
#   2. Generate a debug signing keystore (one-time) so the APK is installable.
#   3. Run Gradle assembleDebug and copy the APK to ./output/.
#
# All downloads go through $PROXY if set. Example:
#   PROXY="socks5://127.0.0.1:<port>" ./build.sh
# Leave it unset for a direct connection.
set -euo pipefail

PROXY="${PROXY:-}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$PROJECT_DIR/.tools"
SDK_DIR="$TOOLS_DIR/android-sdk"
JDK_DIR="$TOOLS_DIR/jdk-17"
OUTPUT_DIR="$PROJECT_DIR/output"

JDK_TAR="OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.13_11.tar.gz"
JDK_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/$JDK_TAR"
CMDLINE_ZIP="commandlinetools-mac-11076708_latest.zip"
CMDLINE_URL="https://dl.google.com/android/repository/$CMDLINE_ZIP"

mkdir -p "$TOOLS_DIR" "$OUTPUT_DIR"

curl_p() {
  if [ -n "$PROXY" ]; then
    curl --proxy "$PROXY" --http1.1 -fL "$@"
  else
    curl --http1.1 -fL "$@"
  fi
}

echo "===== [1/4] JDK 17 ====="
if [ ! -x "$JDK_DIR/Contents/Home/bin/java" ] && [ ! -x "$JDK_DIR/bin/java" ]; then
    echo "Downloading Temurin JDK 17 ..."
    cd "$TOOLS_DIR"
    curl_p -o "$JDK_TAR" "$JDK_URL"
    tar -xzf "$JDK_TAR"
    # Temurin mac tarball extracts to jdk-17.0.13+11/
    mv "jdk-17.0.13+11" "$JDK_DIR" 2>/dev/null || mv "$(find . -maxdepth 1 -type d -name 'jdk-17*' | head -1)" "$JDK_DIR"
fi
if [ -x "$JDK_DIR/Contents/Home/bin/java" ]; then
    export JAVA_HOME="$JDK_DIR/Contents/Home"
else
    export JAVA_HOME="$JDK_DIR"
fi
export PATH="$JAVA_HOME/bin:$PATH"
java -version

echo "===== [2/4] Android SDK cmdline-tools ====="
if [ ! -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "Downloading Android cmdline-tools ..."
    cd "$TOOLS_DIR"
    curl_p -o "$CMDLINE_ZIP" "$CMDLINE_URL"
    unzip -q "$CMDLINE_ZIP" -d "$SDK_DIR/cmdline-tools"
    mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
fi
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
export PATH="$SDK_DIR/cmdline-tools/latest/bin:$PATH"

echo "===== [3/4] SDK packages (platform 34, build-tools 34.0.0) ====="
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platforms;android-34" "build-tools;34.0.0" >/dev/null

echo "===== [4/4] Build APK ====="
# Gradle wrapper jar is not bundled (binary); use system gradle if present,
# otherwise download the distribution.
if command -v gradle >/dev/null 2>&1; then
    GRADLE=gradle
else
    GRADLE_ZIP="gradle-8.5-bin.zip"
    if [ ! -x "$TOOLS_DIR/gradle-8.5/bin/gradle" ]; then
        echo "Downloading Gradle 8.5 ..."
        cd "$TOOLS_DIR"
        curl_p -o "$GRADLE_ZIP" "https://services.gradle.org/distributions/$GRADLE_ZIP"
        unzip -q "$GRADLE_ZIP"
    fi
    GRADLE="$TOOLS_DIR/gradle-8.5/bin/gradle"
fi

# Local.properties points Gradle at the SDK.
echo "sdk.dir=$SDK_DIR" > "$PROJECT_DIR/local.properties"

cd "$PROJECT_DIR"
"$GRADLE" assembleDebug --no-daemon

APK=$(find "$PROJECT_DIR/app/build/outputs/apk/debug" -name '*.apk' | head -1)
cp "$APK" "$OUTPUT_DIR/adb-wifi-widget-debug.apk"
echo ""
echo "===== DONE ====="
echo "APK: $OUTPUT_DIR/adb-wifi-widget-debug.apk"
echo "Next: push APK + device scripts to phone, see README.md"
