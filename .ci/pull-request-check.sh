#!/usr/bin/env bash

set -euo pipefail

# build the cli so we can test it builds
make go_build

# Build the images
make BUILD_ARGS="--no-cache" build

make TAG=latest-amd64 ARCHITECTURE=amd64 tag
# make TAG=latest-arm64 ARCHITECTURE=arm64 tag
