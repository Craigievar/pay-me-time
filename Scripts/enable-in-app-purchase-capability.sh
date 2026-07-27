#!/bin/sh

set -eu

screenbump_project_file="${1:-PayMeTime.xcodeproj/project.pbxproj}"
screenbump_capability_marker="SystemCapabilities = SCREENBUMP_IN_APP_PURCHASE;"
screenbump_marker_count="$(
    grep -c "$screenbump_capability_marker" "$screenbump_project_file" || true
)"

if [ "$screenbump_marker_count" -ne 1 ]; then
    echo "Expected exactly one Screenbump In-App Purchase capability marker."
    exit 1
fi

perl -0pi -e '
    s/SystemCapabilities = SCREENBUMP_IN_APP_PURCHASE;/SystemCapabilities = {\n\t\t\t\t\t\t\tcom.apple.InAppPurchase = {\n\t\t\t\t\t\t\t\tenabled = 1;\n\t\t\t\t\t\t\t};\n\t\t\t\t\t\t};/
' "$screenbump_project_file"

if ! grep -q "com.apple.InAppPurchase = {" "$screenbump_project_file"; then
    echo "Failed to enable the In-App Purchase target capability."
    exit 1
fi
