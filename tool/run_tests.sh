#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Auto-detect local toolchain if not already on PATH
if [[ -d "$HOME/development/jdk17" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$HOME/development/jdk17}"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
if [[ -d "$HOME/development/flutter/bin" ]]; then
  export PATH="$HOME/development/flutter/bin:$PATH"
fi
if [[ -d "$HOME/Android/Sdk" ]]; then
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
  export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$PATH"
  if ! command -v clang >/dev/null 2>&1; then
    NDK_LLVM_BIN="$(find "$ANDROID_HOME/ndk" -maxdepth 4 -type d -path '*/toolchains/llvm/prebuilt/linux-x86_64/bin' 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -n "$NDK_LLVM_BIN" ]]; then
      export PATH="$NDK_LLVM_BIN:$PATH"
    fi
  fi
fi

usage() {
  cat <<EOF
Usage: ./tool/run_tests.sh <suite> [extra args]

Suites:
  lint         Format check + flutter analyze + TDD/offline policy checks
  smoke        Fast smoke test (launch, load library, play & stop one sound)
  unit         Pure Dart unit tests (domain, data, audio, state)
  widget       Flutter widget tests (UI, modes, accessibility)
  integration  End-to-end integration_test suite on Android emulator/device
  all          Run lint, unit, widget, and smoke
  all-e2e      Run all + integration
  build        Build Android debug APK and audit AndroidManifest permissions
EOF
}

run_lint() {
  echo "==> Running policy & TDD checks..."
  python3 .agents/skills/tdd-cycle/scripts/tdd_check.py

  echo "==> Checking Dart formatting..."
  local fmt_targets=()
  for d in lib test integration_test; do
    [[ -d "$d" ]] && fmt_targets+=("$d")
  done
  if [[ ${#fmt_targets[@]} -gt 0 ]]; then
    dart format --output=none --set-exit-if-changed "${fmt_targets[@]}"
  fi

  echo "==> Running flutter analyze..."
  flutter analyze --fatal-infos
}

run_smoke() {
  echo "==> Running smoke suite..."
  flutter test test/smoke_test.dart "$@"
}

run_unit() {
  echo "==> Running unit test suite..."
  local dirs=()
  for d in test/domain test/data test/audio test/state; do
    if [[ -d "$d" ]] && find "$d" -name '*_test.dart' | grep -q .; then
      dirs+=("$d")
    fi
  done
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "No unit test directories found yet."
    return 0
  fi
  flutter test "${dirs[@]}" "$@"
}

run_widget() {
  echo "==> Running widget test suite..."
  if [[ -d "test/ui" ]] && find test/ui -name '*_test.dart' | grep -q .; then
    flutter test test/ui "$@"
  else
    echo "No widget tests found yet."
  fi
}

run_integration() {
  echo "==> Running integration_test suite..."
  if [[ ! -d "integration_test" ]] || ! find integration_test -name '*_test.dart' | grep -q .; then
    echo "No integration tests found."
    return 1
  fi
  flutter test integration_test "$@"
}

run_build() {
  echo "==> Auditing main AndroidManifest.xml for INTERNET permission..."
  python3 .agents/skills/tdd-cycle/scripts/tdd_check.py
  echo "==> Building Android debug APK..."
  flutter build apk --debug "$@"
  echo "==> APK built at: build/app/outputs/flutter-apk/app-debug.apk"
}

CMD="${1:-}"
if [[ -z "$CMD" ]]; then
  usage
  exit 2
fi
shift || true

case "$CMD" in
  lint)        run_lint "$@" ;;
  smoke)       run_smoke "$@" ;;
  unit)        run_unit "$@" ;;
  widget)      run_widget "$@" ;;
  integration) run_integration "$@" ;;
  all)
    run_lint
    run_unit
    run_widget
    run_smoke
    ;;
  all-e2e)
    run_lint
    run_unit
    run_widget
    run_smoke
    run_integration "$@"
    ;;
  build)       run_build "$@" ;;
  *)
    usage
    exit 2
    ;;
esac
