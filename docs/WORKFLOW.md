# Development Workflow & Agent Architecture

This document explains the Phase 0 agent workflow designed for building the offline tabletop RPG soundboard using Antigravity's native customization mechanisms.

## Why This Design
This is a focused, single-user Flutter app. Rather than a bloated org chart, the workflow uses **one coordinator + three small, strictly scoped subagents**, backed by **mechanical policy guards** so TDD and offline invariants are enforced by tooling rather than good intentions.

## Components Created

### 1. Persistent Project Context (`GEMINI.md`)
Placed at the repository root so Antigravity automatically injects it into the coordinator and every subagent:
- Product priority hierarchy (mid-session ergonomics > 100% offline > everything else).
- Strict layer boundaries (`domain/` pure Dart, `audio/`, `data/`, `state/`, `ui/`).
- Canonical test, lint, and build commands (`./tool/run_tests.sh <suite>`).
- Definition of Done checklist for every phase.

### 2. Three Well-Scoped Subagents (`.agents/agents/`)
Stored as version-controlled specifications and instantiated with `define_subagent`:
- **`test-author`** (`.agents/agents/test-author.md`): Owns the **Red** step. Writes deterministic unit/widget/integration tests under `test/` and `integration_test/` only, runs them, and proves they fail before production code exists.
- **`implementer`** (`.agents/agents/implementer.md`): Owns the **Green + Refactor** steps. Writes minimal code under `lib/` to satisfy the failing tests without weakening or skipping tests.
- **`reviewer`** (`.agents/agents/reviewer.md`): Independent **read-only** reviewer (`EnableWriteTools: false`). Structurally prevented from writing code and never reviews code it authored. Audits every phase diff for TDD integrity, domain semantics, edge cases, Material 3/accessibility compliance, and offline/privacy guarantees, returning `VERDICT: APPROVE` or `VERDICT: CHANGES_REQUESTED`.

### 3. Mechanical TDD & Offline Enforcement (`.agents/hooks.json` + `.agents/hooks/tdd_guard.py` + `tdd_check.py`)
Good intentions drift under time pressure, so three automated gates enforce the rules:
1. **Antigravity `PreToolUse` Hook** (`.agents/hooks.json` -> `.agents/hooks/tdd_guard.py`):
   - Blocks creating new production files under `lib/<layer>/` if no corresponding test file exists yet in `test/<layer>/`.
   - Blocks writing `skip: true` into any test file.
   - Blocks adding `android.permission.INTERNET` to `android/app/src/main/AndroidManifest.xml`.
   - Runs `tdd_check.py --staged` before `git commit` (allowing `test(red):` commits during the Red step and `chore(workflow):` / `docs:` commits).
2. **Static Policy Checker** (`.agents/skills/tdd-cycle/scripts/tdd_check.py`):
   - Verifies zero skipped tests, zero `INTERNET` permission in main Android manifest, pure-Dart `lib/domain/` (no Flutter/plugin imports), and test presence for every populated layer.
   - Executed both in `./tool/run_tests.sh lint` and version-controlled in `.githooks/pre-commit` (`git config core.hooksPath .githooks`).
3. **Git History Visibility**:
   - Failing tests are committed first (`test(red): ...`) followed by minimal passing implementation (`feat:` / `fix:`), making Red -> Green progression auditable in `git log`.

### 4. On-Demand Skills (`.agents/skills/`)
Loaded progressively when needed to keep context lean:
- **`tdd-cycle`** (`.agents/skills/tdd-cycle/SKILL.md`): Red -> Green -> Refactor runbook and policy checker script.
- **`code-review`** (`.agents/skills/code-review/SKILL.md`): Detailed review rubric used by `reviewer`.
- **`phase-gate`** (`.agents/skills/phase-gate/SKILL.md`): End-of-phase verification, independent review loop, and commit protocol.

## Phase Cadence
1. **Phase 0**: Workflow setup & commit (before any app code).
2. **Phase 1**: Flutter project skeleton, tooling (`tool/run_tests.sh`), synthesized demo/test WAV fixtures, and first smoke test.
3. **Phase 2**: Pure Dart playback domain (state machine, fades, crossfades, retrigger, Stop All) + `AudioEngine` interface + `SoLoudAudioEngine` adapter.
4. **Phase 3**: Play-mode Material 3 UI, unmistakable pad states, responsive grid, persistent Now Playing bar, master volume & Stop All.
5. **Phase 4**: Folders (create, rename, reorder, delete), explicit Edit Mode, drag reorder, move across folders, pad editor (label, color, icon, type, volume, fades, retrigger).
6. **Phase 5**: Multi-file audio library import (mp3/ogg/wav/flac/m4a) copied to app-private storage, corrupt/missing file handling, single-file ZIP backup export & import.
7. **Phase 6**: Background playback (`audio_service`), audio focus handling (`audio_session` — notifications don't stop music; calls pause & resume), keep-screen-awake (`wakelock_plus`), cold-start state restoration without auto-resume.
8. **Phase 7**: End-to-end `integration_test` suite on Android emulator, debug APK build & manifest audit, final `reviewer` pass, documentation (`README.md`, `docs/ARCHITECTURE.md`), and final report.
