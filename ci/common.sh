#!/usr/bin/env bash
set -euo pipefail
CI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CI_ROOT"
mkdir -p build/evidence build/logs build/results
ci_step() {
  CI_STEP="$1"
  python3 ci/evidence.py start "$CI_STEP"
  trap 'ci_exit=$?; trap - EXIT; python3 ci/evidence.py finish "$CI_STEP" "$ci_exit"; exit "$ci_exit"' EXIT
}
ci_macos() {
  if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'BLOCKED: this step requires a macOS Codemagic runner with Xcode.' >&2
    exit 2
  fi
}
ci_version() {
  IOS_VERSION="${IOS_VERSION:-1.0.0}"
  IOS_BUILD_NUMBER="${IOS_BUILD_NUMBER:-$(python3 -c 'import os; print(int(os.environ.get("PROJECT_BUILD_NUMBER", "1")) + 1)')}"
  export IOS_VERSION IOS_BUILD_NUMBER
  python3 -c 'import os,re; assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",os.environ["IOS_VERSION"]); assert re.fullmatch(r"[1-9][0-9]{0,8}",os.environ["IOS_BUILD_NUMBER"])'
}
