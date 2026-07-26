#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_file="$project_dir/Config/PostHog.local.xcconfig"

if [ -z "${SCREENBUMP_POSTHOG_KEY:-}" ]; then
    echo "SCREENBUMP_POSTHOG_KEY is not set; PostHog will remain disabled."
    exit 0
fi

umask 077
printf 'SCREENBUMP_POSTHOG_KEY = %s\n' "$SCREENBUMP_POSTHOG_KEY" > "$output_file"
echo "Configured the local Screenbump PostHog project token."
