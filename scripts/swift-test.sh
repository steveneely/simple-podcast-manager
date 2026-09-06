#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
repo_hash=$(printf '%s' "$repo_root" | shasum | awk '{print substr($1, 1, 12)}')
cache_root="${TMPDIR%/}/simple-podcast-manager-swift-${repo_hash}"
test_timeout_seconds=${SPM_TEST_TIMEOUT_SECONDS:-300}

if [[ ! "$test_timeout_seconds" =~ '^[0-9]+$' ]]; then
  print -u2 "SPM_TEST_TIMEOUT_SECONDS must be a nonnegative integer."
  exit 2
fi

mkdir -p "${cache_root}/clang-module-cache" "${cache_root}/swiftpm-cache" "${cache_root}/build"

cd "$repo_root"

run_tests() {
  env \
    CLANG_MODULE_CACHE_PATH="${cache_root}/clang-module-cache" \
    SWIFTPM_CACHE_PATH="${cache_root}/swiftpm-cache" \
    swift test --build-path "${cache_root}/build" "$@"
}

if (( test_timeout_seconds == 0 )); then
  run_tests "$@"
  exit $?
fi

watchdog_pid=""
runner_pid=$$

cleanup_test_processes() {
  if [[ -n "$watchdog_pid" ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi
  pkill -TERM -P "$runner_pid" 2>/dev/null || true
}
trap cleanup_test_processes EXIT INT TERM

(
  sleep "$test_timeout_seconds"
  if kill -0 "$runner_pid" 2>/dev/null; then
    print -u2 "Test suite timed out after ${test_timeout_seconds} seconds."
    pkill -TERM -P "$runner_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

if run_tests "$@"; then
  test_status=0
else
  test_status=$?
fi

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""

exit "$test_status"
