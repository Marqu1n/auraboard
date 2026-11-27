#!/usr/bin/env python3
"""Antigravity PreToolUse hook enforcing TDD and offline privacy policies.

Rules enforced mechanically:
1. On write_file/edit_file targeting lib/*.dart (excluding main.dart and
   barrel/export-only files): require that at least one test file exists under
   test/ for the corresponding layer (domain, audio, data, state, ui) before
   production code can be created.
2. On write_file/edit_file targeting test/*.dart: deny introducing `skip: true`
   to prevent weakening or bypassing tests.
3. On write_file/edit_file targeting android/app/src/main/AndroidManifest.xml:
   deny adding `android.permission.INTERNET`.
4. On run_command containing `git commit`: run tdd_check.py (unless the commit
   is explicitly a Phase 0 workflow/docs commit or a test(red): commit).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


def allow(reason: str = "") -> None:
    out = {"decision": "allow"}
    if reason:
        out["reason"] = reason
    print(json.dumps(out))
    sys.exit(0)


def deny(reason: str) -> None:
    print(json.dumps({"decision": "deny", "reason": reason}))
    sys.exit(0)


def check_file_write(workspace: Path, tool_args: dict) -> None:
    raw_path = tool_args.get("Path") or ""
    if not raw_path:
        allow()

    try:
        rel = Path(raw_path).resolve().relative_to(workspace.resolve())
    except ValueError:
        allow()

    rel_str = rel.as_posix()
    content = tool_args.get("Content") or tool_args.get("Replacement") or ""

    # Policy 1: Never allow INTERNET permission in main AndroidManifest.xml
    if rel_str == "android/app/src/main/AndroidManifest.xml":
        if "android.permission.INTERNET" in content:
            deny(
                "Offline Policy Guard: android.permission.INTERNET is forbidden "
                "in android/app/src/main/AndroidManifest.xml."
            )

    # Policy 2: Never allow introducing skip: true in tests
    if rel_str.startswith("test/") or rel_str.startswith("integration_test/"):
        if re.search(r"\bskip\s*:\s*true\b", content):
            deny(
                "TDD Guard: Do not skip tests (skip: true). Fix the root cause "
                "or explain a corrected test explicitly."
            )
        allow()

    # Policy 3: Require tests before creating new production Dart files in lib/
    if rel_str.startswith("lib/") and rel_str.endswith(".dart"):
        exempt = {"lib/main.dart", "lib/app.dart"}
        if rel_str in exempt or Path(workspace / rel).exists():
            allow()

        parts = rel.parts  # ('lib', '<layer>', ...)
        layer = parts[1] if len(parts) > 2 else ""
        test_root = workspace / "test"

        # Check for any test file in test/<layer>/ or matching stem anywhere in test/
        stem = rel.stem
        layer_tests = list((test_root / layer).rglob("*_test.dart")) if layer and (test_root / layer).exists() else []
        stem_tests = list(test_root.rglob(f"*{stem}*_test.dart")) if test_root.exists() else []
        any_tests = list(test_root.rglob("*_test.dart")) if test_root.exists() else []

        if not layer_tests and not stem_tests:
            # Allow pure model/interface files only if layer tests exist; otherwise block
            if layer in {"domain", "audio", "data", "state", "ui"}:
                deny(
                    f"TDD Guard: Cannot create new production file '{rel_str}' before "
                    f"writing a failing test in 'test/{layer}/' (or matching '*{stem}*_test.dart'). "
                    "Write the failing test first (Red -> Green -> Refactor)."
                )
            elif not any_tests:
                deny(
                    f"TDD Guard: Cannot create '{rel_str}' before any test exists in test/."
                )

    allow()


def check_command(workspace: Path, tool_args: dict) -> None:
    cmd = tool_args.get("CommandLine") or ""
    if "git commit" not in cmd:
        allow()

    # Allow Red-phase test commits and workflow/docs-only commits without running full lib checks
    if re.search(r"test\(red\)|chore\(workflow\)|docs:", cmd):
        allow()

    checker = workspace / ".agents" / "skills" / "tdd-cycle" / "scripts" / "tdd_check.py"
    if checker.exists():
        res = subprocess.run(
            [sys.executable, str(checker), "--staged"],
            cwd=str(workspace),
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            msg = (res.stdout + "\n" + res.stderr).strip()
            deny(f"Pre-commit TDD/Policy Guard failed:\n{msg}")

    allow()


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        allow()

    workspace = Path(payload.get("cwd") or os.getcwd())
    tool_call = payload.get("toolCall") or {}
    tool_name = tool_call.get("name") or ""
    tool_args = tool_call.get("args") or {}

    if tool_name in {"write_file", "edit_file"}:
        check_file_write(workspace, tool_args)
    elif tool_name == "run_command":
        check_command(workspace, tool_args)
    else:
        allow()


if __name__ == "__main__":
    main()
