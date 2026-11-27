# Architecture & Product Decisions Log

Concise log of stack choices and ambiguity resolutions, each favoring mid-session tabletop usability and 100% offline reliability.

## Phase 0 — Workflow & Stack Evaluation

- **Workflow structure (Antigravity native)**: Used `GEMINI.md` for always-on context, `.agents/hooks.json` + `.agents/hooks/tdd_guard.py` + `tdd_check.py` for mechanical TDD/privacy enforcement, `.agents/skills/` for progressive runbooks, and 3 subagent roles (`test-author`, `implementer`, read-only `reviewer`) to stay proportional to a small app.
- **Audio engine (`flutter_soloud ^5.4.0`, published 2026-11-26)**: Chosen over `just_audio ^0.10.6` and `audioplayers ^6.8.1` because `flutter_soloud` uses Dart FFI + C++ SoLoud/miniaudio for true low-latency polyphonic playback, sample-accurate gapless looping, native DSP volume faders (`fadeVolume` + `scheduleStop`), and Android NDK `MediaCodec` support for MP3/OGG/WAV/FLAC/M4A — whereas `just_audio` lacks native low-latency polyphony/faders and `audioplayers` suffers from Android loop gaps on compressed audio.
- **Audio abstraction (`AudioEngine` + `Clock`)**: Wrapped `flutter_soloud` behind a thin `AudioEngine` interface and injectable `Clock` so all playback rules, music exclusivity, crossfades, and fade state transitions are unit-tested deterministically without native audio hardware.
- **State management & DI (`flutter_riverpod ^3.5.0`)**: Chosen for clean compile-safe DI via `ProviderScope.overrides` in unit/widget/integration tests without code-generation friction.
- **Persistence (Atomic JSON file in app-private storage)**: Chosen over SQLite (`sqflite`/`drift`) because a single-user soundboard has a small structured graph (folders, pads, settings), atomic temp-file-plus-rename writes are crash-safe, pure Dart VM tests run without native SQLite FFI bindings, and the schema maps 1:1 to the portable backup archive manifest.
- **App name & branding (`AuraBoard` / `auraboard`)**: Named per user specification; Dart package `auraboard`, Android applicationId `com.auraboard.auraboard`, backup file extension `.auraboard` (standard ZIP container).
- **Backup format (`.auraboard` ZIP archive via `archive ^4.7.1`)**: Single portable file containing `manifest.json` (versioned schema with folders, pads, settings) plus `audio/<id>.<ext>` blobs, avoiding external storage path dependencies when migrating devices offline.
- **Background & audio focus (`audio_service ^0.18.19` + `audio_session ^0.2.4`)**: Standard actively maintained Flutter plugins for Android foreground media service (keeps playback alive with screen locked) and OS audio-focus negotiation (ignore/duck short notifications; pause on phone calls and resume after).
- **Keep screen awake (`wakelock_plus ^1.8.2`)**: Actively maintained wakelock plugin toggled from settings/quick action for long GM sessions.
- **Dynamic Material 3 color (`dynamic_color ^2.1.0`)**: Uses Android 12+ wallpaper Material You palettes when available and falls back to a dark-first warm tavern-amber/obsidian seed scheme.
- **End-to-end testing (`integration_test` SDK package)**: Chosen over Patrol to avoid extra native test-runner Gradle complexity while cleanly supporting real Android emulator runs for all required user journeys; system file-picker interactions are bridged via an injectable `FilePickerGateway` override in E2E tests while verifying real file copy, playback, persistence, and UI flows on-device.
- **Typography & Icons (bundled Material Icons + system/bundled font)**: Avoid `google_fonts` runtime downloads so zero network calls ever occur; use Material 3 bundled Material Symbols/Icons (`uses-material-design: true`).

## Phase 1 — Project Skeleton & Tooling

- **Material 3 import (`package:material_ui/material_ui.dart`)**: Flutter 3.50.1 deprecates `package:flutter/material.dart` in favor of `material_ui`, so UI files import `material_ui` directly to stay zero-info clean under `flutter analyze --fatal-infos`.
- **Linux test-host native compiler fallback (`tool/run_tests.sh`)**: `flutter_soloud ^5.4.0` uses Dart native build hooks requiring `clang` on Linux host during `flutter test`; `tool/run_tests.sh` automatically falls back to Android NDK's bundled `clang` when system `clang` is not installed.

## Phase 2 — Playback Domain & Audio Engine

- **Effect retrigger vs. loop toggle**: Tapping an active Music or Ambience pad always fades it out and stops it; tapping an active Effect pad executes its configured `RetriggerMode` (`restart` stops the active voice and replays from 0:00; `layer` overlaps a new voice) so a GM can fire rapid back-to-back SFX, while explicit `stopPad()` (exposed via the Now Playing bar) or `stopAll()` stops any active Effect immediately (or via its per-pad fade-out override).
- **`PlaybackState` lives in `lib/domain/`**: Moved `PlaybackState` alongside `PlaybackEngine` in pure Dart so domain, state, and UI share one immutable state snapshot without circular dependencies.
- **`SoLoudBridge` seam**: `SoLoudAudioEngine` delegates native calls through a thin `SoLoudBridge` interface backed by `SoLoud.instance` in production, enabling deterministic unit testing of caching, clamping, handle lifecycle, and error wrapping without audio hardware.
