#!/usr/bin/env bash

set -euo pipefail

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z ${GITHUB_TOKEN} ]]
then
  echo "No GITHUB_TOKEN set; downloads may be rate-limited"
else
  echo "GITHUB_TOKEN set"
fi

# Build the images
make BUILD_ARGS="--no-cache --build-arg GITHUB_TOKEN=${GITHUB_TOKEN}" build-image-amd64
# make BUILD_ARGS="--no-cache" build-image-arm64

make TAG=latest-amd64 ARCHITECTURE=amd64 tag
# make TAG=latest-arm64 ARCHITECTURE=arm64 tag

make registry-login
make TAG=latest-amd64 ARCHITECTURE=amd64 push
# make TAG=latest-arm64 ARCHITECTURE=arm64 push

make build-manifest
make push-manifest
