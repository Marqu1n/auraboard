# AuraBoard Architecture

## Layer Overview & Dependency Direction
AuraBoard enforces a strict inward dependency boundary (`ui -> state -> domain <- data/audio`), mechanically verified by `.agents/skills/tdd-cycle/scripts/tdd_check.py`:

```
┌─────────────────────────────────────────────────────────────┐
│  lib/ui/         Material 3 screens, PadTile, NowPlayingBar │
│                  Edit Mode, Pad/Folder/Settings sheets      │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  lib/state/      Riverpod 3 providers & acyclic notifiers   │
│                  LibraryController, PlaybackController,     │
│                  EditModeController, sessionResilienceProvider│
└──────────────┬───────────────────────────────┬──────────────┘
               ▼                               ▼
┌──────────────────────────────┐  ┌───────────────────────────┐
│  lib/domain/ (100% Pure Dart)│  │  lib/data/ & lib/audio/   │
│  - models.dart               │  │  - FileLibraryRepository  │
│  - clock.dart                │◄─┤  - AudioFileStore         │
│  - audio_engine.dart         │  │  - BackupService          │
│  - playback_engine.dart      │  │  - FilePickerGateway      │
│  - library_operations.dart   │  │  - SoLoudAudioEngine      │
└──────────────────────────────┘  │  - SessionResilience      │
                                  └───────────────────────────┘
```

- **`lib/domain/`** has **zero** imports of Flutter, `material_ui`, `flutter_riverpod`, or any native plugin. Every playback rule, fade/crossfade transition, and library mutation is unit-tested deterministically via `FakeAudioEngine` and `FakeClock`.

## Playback Engine & State Machine (`lib/domain/playback_engine.dart`)
Each active pad tracks a `_VoiceRecord` with one or more `_LayerInstance` handles and transitions cleanly across `PadPlaybackPhase`:

- **`idle` -> `fadingIn` -> `playing`**: Music & Ambience pads start at volume `0.0` with `looping: true` and fade to `pad.volume` via `AudioEngine.fadeVolume`, transitioning to `playing` when the `Clock` fade timer fires. Effects start immediately (`looping: false`) unless a per-pad `fadeInMsOverride` is configured.
- **Music exclusivity & crossfades**: Starting Music B while Music A is `playing` or `fadingIn` transitions A to `fadingOut` (`fadeVolume(0.0)` + `scheduleStop`) and starts B `fadingIn` over `padB.crossfadeMsOverride ?? settings.defaultCrossfadeMs`. Starting Music C mid-crossfade fades B out while A finishes fading out, guaranteeing only C remains playing.
- **Effect retriggering**: Tapping an active Effect pad executes `RetriggerMode.restart` (stops existing handle and restarts from `0:00`) or `RetriggerMode.layer` (adds a concurrent handle and increments `activeLayerCount`). A `50ms` periodic progress timer updates `position` while effects are active and cancels automatically when idle (`activeTimerCount == 0`).
- **Stop & Stop All**: Looping pads always fade out over `fadeOutMsOverride ?? settings.defaultFadeOutMs` instead of hard-cutting. `stopAll()` smoothly fades every active voice without restarting pads already `fadingOut`.
- **Concurrency & error safety**: Per-pad, music, and global generation tokens abort stale in-flight `loadSource`/`play` calls and stop leaked handles. `AudioLoadException` places only the affected pad in `PadPlaybackPhase.error` while cleaning up prior handles and leaving other active audio undisturbed.

## Audio Engine Adapter (`lib/audio/soloud_audio_engine.dart`)
- Wraps `flutter_soloud ^5.4.0` (C++ SoLoud + `miniaudio` via Dart FFI + Android NDK `MediaCodec` for MP3/OGG/WAV/FLAC/M4A) behind `AudioEngine` and a thin `SoLoudBridge` seam.
- Caches loaded sources per `(path, isAsset)` with in-flight deduplication, validates local file existence before native load, clamps all volumes to `[0.0, 1.0]`, prunes expired handles opportunistically, and tracks active handles for `pauseAll()` / `resumeAll()`.

## Persistence, Private Storage & Offline Backup (`lib/data/`)
- **`FileLibraryRepository`**: Stores `SoundLibrary` as UTF-8 JSON in `<appSupportDir>/library.json` using serialized FIFO writes (`library.json.tmp` -> `flush` -> atomic `rename`). Corrupt or schema-invalid JSON is backed up (`library.json.corrupt.<ts>`) before re-seeding the demo board.
- **`AudioFileStore`**: Copies imported audio (`mp3`, `ogg`, `wav`, `flac`, `m4a`) atomically into `<appSupportDir>/audio/<uuid>.<ext>` (supporting both file paths and Android SAF bytes). Private deletion enforces normalized path containment and symlink checks.
- **`BackupService`**: Exports a single `.auraboard` ZIP archive containing `manifest.json` (`backupVersion: 1`, portable `audio/<name>` paths) and deduplicated audio blobs. Import validates every archive entry (blocking `..`, absolute paths, drive letters, null bytes, and symlinks) before touching disk, extracts only referenced audio entries, and rolls back extracted files on any failure.

## Background Playback & Session Resilience (`lib/audio/session_resilience.dart`)
- **`SessionResilienceCoordinator`** serializes and coalesces playback state syncs onto:
  - **`PlatformAudioFocusGateway` (`audio_session`)**: Configured with `AudioSessionConfiguration.music().copyWith(androidWillPauseWhenDucked: false)`. Transient `duck` events (notifications) are ignored; `pause` interruptions (phone calls) pause active audio & fade timers and resume cleanly when ended; permanent `unknown` focus loss pauses without wedging future interruptions.
  - **`PlatformBackgroundServiceGateway` (`audio_service`)**: Lazily initializes an Android `mediaPlayback` foreground service (`androidStopForegroundOnPause: false` for Android 12+ lock-screen resume safety) with a lock-screen Stop action wired to `stopAll()`.
  - **`PlatformWakelockGateway` (`wakelock_plus`)**: Applies persisted `BoardSettings.keepScreenAwake`.

## Riverpod 3 Acyclic Provider Graph (`lib/state/providers.dart`)
Strict one-way dependencies prevent `CircularDependencyError`:
- `sessionResilienceProvider` -> `libraryControllerProvider`, `playbackControllerProvider`, and session gateways.
- `playbackControllerProvider` -> `libraryControllerProvider`, `audioEngineProvider`, `clockProvider`.
- `libraryControllerProvider` -> `libraryRepositoryProvider`, `audioFileStoreProvider`, `backupServiceProvider`.
