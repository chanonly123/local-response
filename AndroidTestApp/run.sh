#!/bin/bash

# Build, install and run AndroidTestApp on a connected device, then tail its logs.
# Usage: ./run.sh [-clean] [-release] [-s SERIAL] [-tags]

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE="com.chanonly123.androidtestapp"
ACTIVITY=".MainActivity"
# The tags worth seeing when you only care about the intercepted traffic.
# OkHttp is what HttpLoggingInterceptor writes under; add tags here as the
# library starts logging under its own.
LOG_TAGS=(OkHttp)

cd "$PROJECT_DIR"

# The SDK lives outside the repo, so honour an existing environment first and
# fall back to the Homebrew command-line-tools location (no Android Studio).
if [ -z "$ANDROID_HOME" ]; then
    ANDROID_HOME="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
fi
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"

if [ -z "$JAVA_HOME" ]; then
    # The Gradle Android plugin needs a JDK 17+; Homebrew's openjdk@21 is not
    # symlinked into /usr/bin, so point at it directly.
    for candidate in /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
                     /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home; do
        if [ -d "$candidate" ]; then
            JAVA_HOME="$candidate"
            break
        fi
    done
fi
export JAVA_HOME

ADB="$ANDROID_HOME/platform-tools/adb"
if [ ! -x "$ADB" ]; then
    ADB="$(command -v adb || true)"
fi
if [ -z "$ADB" ]; then
    echo "error: adb not found. Install platform-tools:" >&2
    echo "  sdkmanager \"platform-tools\"" >&2
    exit 1
fi

CLEAN=false
VARIANT=debug
SERIAL=""
TAGS_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        -clean) CLEAN=true ;;
        -release) VARIANT=release ;;
        -s) SERIAL="$2"; shift ;;
        -tags) TAGS_ONLY=true ;;
        *) echo "error: unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

# Every adb call targets the same device, so resolve the serial once here
# instead of letting adb guess differently between install and logcat.
if [ -z "$SERIAL" ]; then
    DEVICES="$("$ADB" devices | awk '$2 == "device" { print $1 }')"
    COUNT="$(printf '%s\n' "$DEVICES" | grep -c . || true)"
    if [ "$COUNT" -eq 0 ]; then
        echo "error: no device connected." >&2
        echo "  Enable USB debugging, then check: adb devices" >&2
        exit 1
    fi
    if [ "$COUNT" -gt 1 ]; then
        echo "error: more than one device connected; pick one with -s SERIAL:" >&2
        printf '  %s\n' $DEVICES >&2
        exit 1
    fi
    SERIAL="$DEVICES"
fi

ADB_CMD=("$ADB" -s "$SERIAL")

MODEL="$("${ADB_CMD[@]}" shell getprop ro.product.model | tr -d '\r')"
echo "Device: $MODEL ($SERIAL)"

if [ "$CLEAN" = true ]; then
    echo "Cleaning build..."
    ./gradlew clean --console=plain
fi

# Capitalised variant name is what the Gradle task expects: assembleDebug.
TASK="assemble$(echo "${VARIANT:0:1}" | tr '[:lower:]' '[:upper:]')${VARIANT:1}"
echo "Building $TASK..."
./gradlew "$TASK" --console=plain

APK="app/build/outputs/apk/$VARIANT/app-$VARIANT.apk"
if [ ! -f "$APK" ]; then
    echo "error: APK not found at $APK" >&2
    exit 1
fi

echo "Installing $APK..."
"${ADB_CMD[@]}" install -r "$APK"

# Clear before launch so the log only shows this run.
"${ADB_CMD[@]}" logcat -c || true

echo "Launching $PACKAGE$ACTIVITY..."
"${ADB_CMD[@]}" shell am start -n "$PACKAGE/$ACTIVITY" > /dev/null

# The process needs a moment to exist before logcat can be pinned to its pid.
PID=""
for _ in $(seq 1 20); do
    PID="$("${ADB_CMD[@]}" shell pidof "$PACKAGE" | tr -d '\r')"
    [ -n "$PID" ] && break
    sleep 0.25
done

if [ -z "$PID" ]; then
    echo "error: app did not start; dumping recent crash log:" >&2
    "${ADB_CMD[@]}" logcat -d -t 200 | grep -iE "AndroidRuntime|FATAL" >&2 || true
    exit 1
fi

# Both filters are ANDed by logcat, so pinning the pid as well keeps a second
# copy of the app on the device from bleeding into the tag-filtered view.
if [ "$TAGS_ONLY" = true ]; then
    echo "Running (pid $PID). Tailing ${LOG_TAGS[*]} — Ctrl-C to stop."
    echo "---"
    exec "${ADB_CMD[@]}" logcat --pid="$PID" -s "${LOG_TAGS[@]}"
fi

echo "Running (pid $PID). Tailing logs — Ctrl-C to stop."
echo "  Network traffic only: ./run.sh -tags"
echo "---"
exec "${ADB_CMD[@]}" logcat --pid="$PID"
