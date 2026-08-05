#!/bin/bash

# Build and run the Local Response Mapper app
# Usage: ./run.sh [-clean]

set -e

# The Xcode project lives in a subdirectory; build from there so the relative
# ./DerivedData path stays next to the project.
APP_DIR="$(cd "$(dirname "$0")/Local_Response_Mapper" && pwd)"
PROJECT="Local Response Mapper.xcodeproj"
SCHEME="Local Response Mapper"
APP="Local Response Mapper.app"

cd "$APP_DIR"

CONFIGURATION=Release

CLEAN=false
for arg in "$@"; do
    case "$arg" in
        -clean) CLEAN=true ;;
    esac
done

if [ "$CLEAN" = true ]; then
    echo "Removing DerivedData..."
    rm -rf ./DerivedData

    echo "Updating package dependencies..."
    rm -f "$PROJECT/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    xcodebuild -resolvePackageDependencies -project "$PROJECT" -scheme "$SCHEME"
fi

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -configuration "$CONFIGURATION" \
    -derivedDataPath ./DerivedData \
    build

echo "Launching app..."
open "./DerivedData/Build/Products/$CONFIGURATION/$APP"
