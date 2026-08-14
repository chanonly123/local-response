#!/bin/bash

# Build and run iOSTestApp on an iOS simulator.
#
# Dependencies come from Swift Package Manager (the local LocalResponse package),
# so there is nothing to install before building.
#
# Usage:
#   ./ios_app_run.sh                 # first available (or already booted) simulator
#   ./ios_app_run.sh -d "iPhone 17"  # pick a simulator by name or UDID
#   ./ios_app_run.sh -clean          # wipe DerivedData + resolved package state first
#   ./ios_app_run.sh -l              # list available simulators and exit

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/iOSTestApp"
PROJECT="$APP_DIR/iOSTestApp.xcodeproj"
SCHEME="iOSTestApp"
CONFIGURATION=Debug
BUNDLE_ID="com.chanonly123.iOSTestApp"
DERIVED_DATA="$APP_DIR/DerivedData"

CLEAN=false
DEVICE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -clean) CLEAN=true ;;
        -d|--device) DEVICE="$2"; shift ;;
        -l|--list)
            xcrun simctl list devices available
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ---------------------------------------------------------------- simulator --

# Prints "UDID Name" per line. Simulator names can contain regex characters, so
# everything downstream matches with grep -F and splits on the first space.
list_sims() {
    xcrun simctl list devices available \
        | grep -E '\([0-9A-Fa-f-]{36}\) \((Booted|Shutdown)\)' \
        | sed -E 's/^ *(.+) \(([0-9A-Fa-f-]{36})\) \((Booted|Shutdown)\).*/\2 \1/'
}

pick_simulator() {
    local sims booted
    sims="$(list_sims)"
    [ -n "$sims" ] || { echo "No available iOS simulators found. Install a runtime in Xcode > Settings > Components." >&2; exit 1; }

    # Explicit request: matches either the UDID or any part of the device name.
    if [ -n "$DEVICE" ]; then
        printf '%s\n' "$sims" | grep -iF -m1 -- "$DEVICE" && return 0
        echo "No simulator matching '$DEVICE'. Try ./ios_app_run.sh -l" >&2
        exit 1
    fi

    # Reuse whatever is already booted so repeat runs stay fast.
    booted="$(xcrun simctl list devices booted \
        | grep -E '\([0-9A-Fa-f-]{36}\) \(Booted\)' \
        | sed -E 's/^ *(.+) \(([0-9A-Fa-f-]{36})\) \(Booted\).*/\2 \1/' \
        | head -1)"
    if [ -n "$booted" ]; then
        printf '%s\n' "$booted"
        return 0
    fi

    printf '%s\n' "$sims" | grep -m1 -E '^[0-9A-Fa-f-]{36} iPhone' \
        || printf '%s\n' "$sims" | head -1
}

SIM="$(pick_simulator)"
SIM_UDID="${SIM%% *}"
SIM_NAME="${SIM#* }"
echo "Simulator: $SIM_NAME ($SIM_UDID)"

# ----------------------------------------------------------------- packages --

if [ "$CLEAN" = true ]; then
    echo "Removing DerivedData..."
    rm -rf "$DERIVED_DATA"
    rm -rf "$PROJECT/project.xcworkspace/xcshareddata/swiftpm"
fi

echo "Resolving Swift packages..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    -resolvePackageDependencies

# -------------------------------------------------------------------- build --

echo "Booting simulator..."
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "id=$SIM_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION-iphonesimulator/$SCHEME.app"
[ -d "$APP_PATH" ] || { echo "Build product not found at $APP_PATH" >&2; exit 1; }

# ------------------------------------------------------------------- launch --

echo "Installing $APP_PATH..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "Launching $BUNDLE_ID..."
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo "Done. Open the 'Local Response Mapper' macOS app (./run.sh) to see the captured traffic."
