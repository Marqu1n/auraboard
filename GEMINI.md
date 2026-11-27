# RPG Soundboard — Project Context & Engineering Conventions

## Mission & Priority Order
Offline-first tabletop RPG soundboard (Flutter, Android primary, iOS-compatible) designed for a single game master running D&D sessions in a dim room with 1-second glances at a phone or tablet.

When any tradeoff arises, prioritize in strict order:
1. **Effortless mid-session operation** — unmistakable visual states without relying on color alone, >= 48dp touch targets, explicit edit mode so nothing breaks by accident in play mode, zero hard audio cuts on loops.
2. **100% offline & private** — zero accounts, analytics, ads, remote assets, or `android.permission.INTERNET` in the release/main Android manifest.

## Architecture Boundaries
Keep strict dependency direction (`ui -> state -> domain <- data/audio`):
- `lib/domain/` — Pure Dart models, playback state machine, fade/crossfade scheduler, folder/pad operations, `AudioEngine` interface, `Clock` interface. **Zero Flutter UI or platform plugin imports.**
- `lib/audio/` — Concrete `AudioEngine` implementation (`SoLoudAudioEngine`), audio session/focus & background service integration (`audio_service`, `audio_session`).
- `lib/data/` — Atomic JSON persistence (`LibraryRepository`), app-private audio file storage (`AudioFileStore`), single-file ZIP backup export/import (`BackupService`), first-run demo board seeder.
- `lib/state/` — Riverpod providers and controllers wiring domain, audio, and persistence.
- `lib/ui/` — Material Design 3 screens, responsive pad grid, play/edit modes, now-playing bar, folder management, settings.

## Canonical Commands
All agents MUST use these documented entrypoints (implemented in `tool/run_tests.sh` starting in Phase 1):
- `./tool/run_tests.sh lint` — Format check (`dart format --output=none --set-exit-if-changed .`) + static analysis (`flutter analyze --fatal-infos`) + workflow/manifest policy checks.
- `./tool/run_tests.sh smoke` — Fast smoke subset proving app launch, library load, and play/stop of one sound.
- `./tool/run_tests.sh unit` — Pure Dart unit tests (playback rules, fades, crossfades, folders/pads, persistence, backup round-trip).
- `./tool/run_tests.sh widget` — Flutter widget tests (pad states, play vs edit mode, now-playing area, accessibility/scaling).
- `./tool/run_tests.sh integration` — End-to-end `integration_test` suite on an Android emulator/device.
- `./tool/run_tests.sh all` — Runs `lint`, `unit`, `widget`, and `smoke` in one command (`all-e2e` also runs `integration`).
- `./tool/run_tests.sh build` — Builds the Android debug APK (`flutter build apk --debug`) and verifies `INTERNET` permission is absent from the main manifest.

## Workflow & Enforced TDD Rules
1. **Red -> Green -> Refactor**:
   - Every behavioral change starts with a failing test written under `test/` BEFORE touching `lib/`.
   - Commit the failing test first (`test(red): ...`) or capture failing output via `test-author` before `implementer` writes production code.
   - Write minimal code to pass (`feat:` / `fix:`), then refactor while keeping tests green.
   - **Never weaken, skip (`skip: true`), or delete a test to get a green run.** If a test is genuinely wrong, fix it explicitly and explain why in the commit message.
2. **Mechanical Enforcement**:
   - `.agents/hooks.json` (`PreToolUse` -> `.agents/hooks/tdd_guard.py`) blocks creating new `lib/` modules without corresponding tests and blocks committing skipped tests or an `INTERNET` permission in `AndroidManifest.xml`.
   - `.agents/skills/tdd-cycle/scripts/tdd_check.py` is also wired into `.githooks/pre-commit` and `./tool/run_tests.sh lint`.
3. **Independent Code Review**:
   - Every phase MUST be reviewed by the read-only `reviewer` subagent (`.agents/agents/reviewer.md`), which did NOT author the code under review and has write tools disabled.
   - Address all blocking findings before tagging/completing a phase.
4. **Decision Logging**:
   - Whenever resolving an ambiguity or making a stack/design choice, append a concise entry to `docs/DECISIONS.md` with a one-line rationale.

## Coding, UI & Accessibility Standards
- Dart strict typing, immutable domain models, `const` constructors where possible.
- Material Design 3 (`useMaterial3: true`), seed color + `dynamic_color` support, dark theme default with light theme toggle.
- Minimum `48dp x 48dp` interactive touch targets.
- Meaningful `Semantics` labels on all pads, playback controls, mode switches, and volume sliders.
- Layouts must remain usable and overflow-free at `2.0x` text scale factor on phone and tablet, portrait and landscape.
- Bundle all fonts/icons locally; never fetch fonts or assets over the network.

## Definition of Done (Per Phase)
A phase is NOT done until ALL of the following are true:
- [ ] Every new behavior followed Red -> Green -> Refactor (visible in git history).
- [ ] `./tool/run_tests.sh all` passes with zero warnings, zero lint errors, and zero skipped tests.
- [ ] `tdd_check.py` passes (no skipped tests, no `INTERNET` permission in main `AndroidManifest.xml`).
- [ ] Independent `reviewer` subagent reviewed `git diff` and returned `APPROVE`.
- [ ] `docs/DECISIONS.md` updated for any architectural or product decisions made in the phase.
- [ ] Clean git commit created for the phase.
