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

CLEAN=false
for arg in "$@"; do
    case "$arg" in
        -clean) CLEAN=true ;;
    esac
done

if [ "$CLEAN" = true ]; then
    echo "Cleaning..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -destination 'platform=macOS' \
        -configuration Release \
        -derivedDataPath ./DerivedData \
        clean
fi

echo "Building $SCHEME..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -configuration Release \
    -derivedDataPath ./DerivedData \
    build

echo "Launching app..."
open "./DerivedData/Build/Products/Release/$APP"
