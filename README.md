# AuraBoard

An **offline-first tabletop RPG soundboard** built with Flutter (Material Design 3) for game masters running live sessions in dim rooms on phones and tablets.

## Highlights
- **Effortless mid-session playback**:
  - **Effects**: low-latency polyphonic one-shots with live progress bars and per-pad retrigger mode (`Restart` or `Layer` with layer badge).
  - **Music**: sample-accurate gapless loops with single-track exclusivity and smooth crossfades (including mid-crossfade interruption safety).
  - **Ambience**: gapless loops that layer freely (e.g., rain + dungeon wind) with smooth fade-in and fade-out.
  - **Unmistakable at-a-glance states**: icons, text badges, borders, loop markers, progress bars, and full `Semantics` labels distinguish `Idle`, `Fading in`, `Playing`, `Fading out`, and `Error` without relying on color alone.
  - **Persistent Now-Playing bar**: lists every active sound across folders with per-item volume and stop controls, plus always-reachable **Master Volume** and smooth **Stop All**.
- **Safe organization & explicit Edit Mode**:
  - Create, rename, reorder, and delete folders; edit pad label, color, optional icon, type, volume, retrigger mode, and per-pad fade/crossfade overrides; drag-and-drop pad reordering and cross-folder moves.
  - Play Mode hides all destructive/edit controls and disables drag gestures so nothing breaks mid-session.
- **100% offline & private**:
  - Zero accounts, telemetry, ads, or remote assets/fonts.
  - `android/app/src/main/AndroidManifest.xml` (release APK) does **not** request `android.permission.INTERNET` at all. *(Flutter's development-only `android/app/src/debug/AndroidManifest.xml` retains `INTERNET` solely so `flutter run`/DevTools/`integration_test` can connect to the Dart VM service in debug builds.)*
  - Multi-file import (`mp3`, `ogg`, `wav`, `flac`, `m4a`) copied atomically into app-private storage.
  - Single-file `.auraboard` ZIP backup export/import (folders, pads, settings, and audio files) for offline device transfer.
  - Bundled copyright-free synthesized WAV demo board (`tool/generate_demo_audio.py`).
- **Session resilience**:
  - Background playback via Android `mediaPlayback` foreground service (`audio_service`) and iOS `UIBackgroundModes: audio` (iOS build unverified on Linux host).
  - OS audio focus handling (`audio_session`): transient notifications do not stop music; phone calls pause and resume playback cleanly.
  - Optional **Keep screen awake** toggle (`wakelock_plus`).
  - Atomic JSON persistence (`FileLibraryRepository`) preserves library and layout across restarts without auto-resuming audio.

## Prerequisites
- **Flutter SDK**: latest stable (verified on Flutter `3.50.1` / Dart `3.14.0`).
- **Android SDK**: API 35/36 platform, build-tools `35.0.0`, NDK `27.x`, CMake `3.22.1`, and JDK 17.
- **Linux host tests**: `flutter_soloud ^5.4.0` uses Dart native build hooks requiring `clang` on Linux host; `./tool/run_tests.sh` automatically falls back to Android NDK's bundled `clang` if system `clang` is not installed.

## Setup & Run
```bash
# Install dependencies
flutter pub get

# (Optional) Regenerate deterministic copyright-free demo WAVs & test fixtures
python3 tool/generate_demo_audio.py

# Run on a connected Android device or emulator
flutter run
```

## Canonical Test, Lint & Build Commands
Every verification suite is exposed through `./tool/run_tests.sh`:

| Command | Purpose |
| :--- | :--- |
| `./tool/run_tests.sh lint` | Policy/TDD/offline manifest check (`tdd_check.py`) + `dart format` check + `flutter analyze --fatal-infos` |
| `./tool/run_tests.sh smoke` | Fast smoke test proving app launch, demo library load, and play/stop of a sound |
| `./tool/run_tests.sh unit` | Pure Dart & data/audio unit tests (playback rules, fades/crossfades, folder/pad ops, atomic persistence, backup round-trip, audio focus/resilience) |
| `./tool/run_tests.sh widget` | Flutter widget tests (pad states, Play vs Edit Mode, Now-Playing bar, import/backup UI, `2.0x` text scaling & `>= 48dp` touch targets) |
| `./tool/run_tests.sh integration` | End-to-end `integration_test/app_e2e_test.dart` on a running Android emulator/device |
| `./tool/run_tests.sh all` | Runs `lint`, `unit`, `widget`, and `smoke` in sequence |
| `./tool/run_tests.sh all-e2e` | Runs `all` plus `integration` |
| `./tool/run_tests.sh build` | Audits `AndroidManifest.xml` for absence of `INTERNET` permission and builds `build/app/outputs/flutter-apk/app-debug.apk` |

## Documentation
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Layer boundaries, playback state machine, persistence & backup format, and background audio design.
- [docs/DECISIONS.md](docs/DECISIONS.md) — Stack choices and ambiguity resolutions with rationales.
- [docs/WORKFLOW.md](docs/WORKFLOW.md) — Phase 0 agent workflow, mechanical TDD enforcement, and independent review structure.
