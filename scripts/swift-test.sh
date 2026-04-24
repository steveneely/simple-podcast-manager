#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
repo_hash=$(printf '%s' "$repo_root" | shasum | awk '{print substr($1, 1, 12)}')
cache_root="${TMPDIR%/}/simple-podcast-manager-swift-${repo_hash}"

mkdir -p "${cache_root}/clang-module-cache" "${cache_root}/swiftpm-cache" "${cache_root}/build"

cd "$repo_root"
env \
  CLANG_MODULE_CACHE_PATH="${cache_root}/clang-module-cache" \
  SWIFTPM_CACHE_PATH="${cache_root}/swiftpm-cache" \
  swift test --build-path "${cache_root}/build" "$@"
