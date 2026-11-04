#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/prepare-deps.sh "$@"
# AppKit suites share NSApplication and Preferences, including across async waits.
swift test --scratch-path "${THERM2_BUILD_PATH:-.build}" --no-parallel "$@"
