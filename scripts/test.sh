#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/prepare-deps.sh "$@"
swift test --scratch-path "${THERM2_BUILD_PATH:-.build}" "$@"
