#!/usr/bin/env python3
"""Static TDD & offline-policy verification script.

Checks:
1. No `skip: true` in any Dart test file under test/ or integration_test/.
2. No `android.permission.INTERNET` in android/app/src/main/AndroidManifest.xml.
3. Every populated layer under lib/{domain,audio,data,state,ui} has corresponding
   test files under test/.
4. When run with --staged, ensures no staged changes violate (1) or (2).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]


def check_no_skipped_tests(root: Path) -> list[str]:
    errors: list[str] = []
    for folder in ("test", "integration_test"):
        base = root / folder
        if not base.exists():
            continue
        for path in sorted(base.rglob("*_test.dart")):
            text = path.read_text(encoding="utf-8", errors="replace")
            for idx, line in enumerate(text.splitlines(), start=1):
                if re.search(r"\bskip\s*:\s*true\b", line):
                    rel = path.relative_to(root).as_posix()
                    errors.append(f"Skipped test forbidden: {rel}:{idx}: {line.strip()}")
    return errors


def check_no_internet_permission(root: Path) -> list[str]:
    manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        return []
    text = manifest.read_text(encoding="utf-8", errors="replace")
    if "android.permission.INTERNET" in text:
        return [
            "Offline policy violation: android/app/src/main/AndroidManifest.xml "
            "must NOT declare android.permission.INTERNET."
        ]
    return []


def check_layer_test_presence(root: Path) -> list[str]:
    errors: list[str] = []
    lib_dir = root / "lib"
    test_dir = root / "test"
    if not lib_dir.exists():
        return []

    for layer in ("domain", "audio", "data", "state", "ui"):
        layer_lib = lib_dir / layer
        if not layer_lib.exists():
            continue
        prod_files = [p for p in layer_lib.rglob("*.dart") if not p.name.endswith(".g.dart")]
        if not prod_files:
            continue
        layer_test = test_dir / layer
        test_files = list(layer_test.rglob("*_test.dart")) if layer_test.exists() else []
        if not test_files:
            errors.append(
                f"TDD coverage gap: lib/{layer}/ has {len(prod_files)} file(s) "
                f"but test/{layer}/ has no *_test.dart files."
            )
    return errors


def check_domain_purity(root: Path) -> list[str]:
    errors: list[str] = []
    domain_dir = root / "lib" / "domain"
    if not domain_dir.exists():
        return []
    forbidden = (
        "package:flutter/",
        "package:material_ui/",
        "package:flutter_riverpod/",
        "package:flutter_soloud/",
        "package:audio_service/",
        "package:audio_session/",
        "package:file_picker/",
        "package:wakelock_plus/",
    )
    for path in sorted(domain_dir.rglob("*.dart")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for idx, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("import "):
                for bad in forbidden:
                    if bad in stripped:
                        rel = path.relative_to(root).as_posix()
                        errors.append(
                            f"Domain purity violation: {rel}:{idx} imports {bad}"
                        )
    return errors


def check_staged_only_red_or_valid(root: Path) -> list[str]:
    res = subprocess.run(
        ["git", "diff", "--cached", "--name-only"],
        cwd=str(root),
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        return []
    staged = [line.strip() for line in res.stdout.splitlines() if line.strip()]
    if not staged:
        return []
    # Run standard invariants against workspace
    return (
        check_no_skipped_tests(root)
        + check_no_internet_permission(root)
        + check_domain_purity(root)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify TDD and offline policy invariants.")
    parser.add_argument("--staged", action="store_true", help="Run pre-commit checks on staged state.")
    args = parser.parse_args()

    if args.staged:
        errors = check_staged_only_red_or_valid(ROOT)
    else:
        errors = (
            check_no_skipped_tests(ROOT)
            + check_no_internet_permission(ROOT)
            + check_layer_test_presence(ROOT)
            + check_domain_purity(ROOT)
        )

    if errors:
        print("TDD/Policy Check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("TDD/Policy Check PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
