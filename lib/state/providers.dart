import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:auraboard/audio/session_resilience.dart';
import 'package:auraboard/audio/soloud_audio_engine.dart';
import 'package:auraboard/data/audio_file_store.dart';
import 'package:auraboard/data/backup_service.dart';
import 'package:auraboard/data/file_picker_gateway.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/audio_engine.dart';
import 'package:auraboard/domain/clock.dart';
import 'package:auraboard/domain/library_operations.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/domain/playback_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

export 'package:auraboard/domain/playback_engine.dart' show PlaybackState;

const Uuid _uuid = Uuid();

const List<int> _importedPadColorPalette = <int>[
  0xFFB84A39,
  0xFFD96B27,
  0xFFC68A32,
  0xFF3A7D44,
  0xFF6A4C93,
  0xFF3E6D8C,
  0xFF4F5D75,
  0xFF9C3D3D,
  0xFFD4A738,
  0xFF2A7B76,
  0xFF43509C,
  0xFF7A4465,
];

/// Summary of an offline multi-file audio import operation.
class ImportAudioResult {
  const ImportAudioResult({
    required this.importedCount,
    required this.skippedCount,
    required this.importedPads,
  });

  final int importedCount;
  final int skippedCount;
  final List<SoundPad> importedPads;
}

/// Provides the active [AudioEngine] implementation.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = SoLoudAudioEngine();
  ref.onDispose(() {
    unawaited(engine.dispose());
  });
  return engine;
});

/// Provides the [Clock] used for playback scheduling and timestamps.
final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

/// Provides the [LibraryRepository] for loading and persisting board data.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return InMemoryLibraryRepository();
});

/// Provides the app-private [AudioFileStore] for imported user audio files.
final audioFileStoreProvider = Provider<AudioFileStore>((ref) {
  return AudioFileStore(baseDirectory: Directory.systemTemp);
});

/// Provides the offline [BackupService] for `.auraboard` ZIP export/import.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(audioFileStore: ref.watch(audioFileStoreProvider));
});

/// Provides the [FilePickerGateway] used for audio import and backup transfer.
final filePickerGatewayProvider = Provider<FilePickerGateway>((ref) {
  return const PlatformFilePickerGateway();
});

/// Provides the platform [AudioFocusGateway] for audio focus and interruptions.
final audioFocusGatewayProvider = Provider<AudioFocusGateway>((ref) {
  return PlatformAudioFocusGateway();
});

/// Provides the platform [BackgroundServiceGateway] for OS media notifications.
final backgroundServiceGatewayProvider = Provider<BackgroundServiceGateway>((
  ref,
) {
  var isDisposed = false;
  ref.onDispose(() {
    isDisposed = true;
  });
  return PlatformBackgroundServiceGateway(
    onStopAll: () async {
      if (!isDisposed) {
        await ref.read(playbackControllerProvider.notifier).stopAll();
      }
    },
  );
});

/// Provides the platform [WakelockGateway] for keeping the screen awake.
final wakelockGatewayProvider = Provider<WakelockGateway>((ref) {
  return const PlatformWakelockGateway();
});

/// Coordinates OS audio focus, interruption pause/resume, foreground media
/// service notifications, and keep-screen-awake wakelock during live sessions.
final sessionResilienceProvider = Provider<SessionResilienceCoordinator>((ref) {
  final audioFocus = ref.watch(audioFocusGatewayProvider);
  final backgroundService = ref.watch(backgroundServiceGatewayProvider);
  final wakelock = ref.watch(wakelockGatewayProvider);

  var isDisposed = false;
  final coordinator = SessionResilienceCoordinator(
    audioFocusGateway: audioFocus,
    backgroundServiceGateway: backgroundService,
    wakelockGateway: wakelock,
    onPauseForInterruption: () async {
      if (!isDisposed) {
        await ref
            .read(playbackControllerProvider.notifier)
            .pauseForInterruption();
      }
    },
    onResumeAfterInterruption: () async {
      if (!isDisposed) {
        await ref
            .read(playbackControllerProvider.notifier)
            .resumeAfterInterruption();
      }
    },
  );

  Map<String, SoundPad> currentPadsById() {
    final library = ref.read(libraryControllerProvider).asData?.value;
    if (library == null) {
      return const <String, SoundPad>{};
    }
    return <String, SoundPad>{for (final pad in library.pads) pad.id: pad};
  }

  final initialLibrary = ref.read(libraryControllerProvider).asData?.value;
  unawaited(
    coordinator.initialize(
      keepScreenAwake: initialLibrary?.settings.keepScreenAwake ?? false,
    ),
  );

  ref.listen<AsyncValue<SoundLibrary>>(libraryControllerProvider, (
    previous,
    next,
  ) {
    if (isDisposed) {
      return;
    }
    final nextLibrary = next.asData?.value;
    if (nextLibrary == null) {
      return;
    }
    final prevLibrary = previous?.asData?.value;
    if (prevLibrary == null ||
        prevLibrary.settings.keepScreenAwake !=
            nextLibrary.settings.keepScreenAwake) {
      unawaited(
        coordinator.setKeepScreenAwake(nextLibrary.settings.keepScreenAwake),
      );
    }
    if (prevLibrary != null && prevLibrary.pads != nextLibrary.pads) {
      final playbackState = ref.read(playbackControllerProvider);
      if (playbackState.activeByPad.isNotEmpty) {
        unawaited(
          coordinator.syncPlaybackState(
            playbackState,
            padsById: <String, SoundPad>{
              for (final pad in nextLibrary.pads) pad.id: pad,
            },
          ),
        );
      }
    }
  });

  ref.listen<PlaybackState>(playbackControllerProvider, (previous, next) {
    if (isDisposed) {
      return;
    }
    unawaited(coordinator.syncPlaybackState(next, padsById: currentPadsById()));
  });

  ref.onDispose(() {
    isDisposed = true;
    unawaited(coordinator.dispose());
  });

  return coordinator;
});

/// Controls whether the soundboard is in explicit Edit Mode (`true`) or safe
/// Play Mode (`false`, default).
final editModeProvider = NotifierProvider<EditModeController, bool>(
  EditModeController.new,
);

class EditModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEditMode(bool enabled) {
    state = enabled;
  }

  void toggle() {
    state = !state;
  }
}

/// Loads and manages the persisted [SoundLibrary].
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, SoundLibrary>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<SoundLibrary> {
  @override
  Future<SoundLibrary> build() async {
    return ref.read(libraryRepositoryProvider).load();
  }

  Future<SoundLibrary> _mutate(
    SoundLibrary Function(SoundLibrary current) transform,
  ) async {
    final current = state.asData?.value ?? await future;
    final updated = transform(current);
    if (updated == current) {
      return updated;
    }
    state = AsyncData<SoundLibrary>(updated);
    await ref.read(libraryRepositoryProvider).save(updated);
    return updated;
  }

  /// Updates persisted [BoardSettings] in memory and storage.
  Future<void> updateSettings(BoardSettings settings) async {
    await _mutate(
      (current) => current.settings == settings
          ? current
          : current.copyWith(settings: settings),
    );
  }

  /// Creates and persists a new folder with a generated unique ID.
  Future<void> createFolder(String name) async {
    final id = 'folder_${_uuid.v4()}';
    await _mutate(
      (current) => LibraryOperations.createFolder(current, id: id, name: name),
    );
  }

  /// Renames the folder matching [folderId] and persists the change.
  Future<void> renameFolder(String folderId, String newName) async {
    await _mutate(
      (current) => LibraryOperations.renameFolder(
        current,
        folderId: folderId,
        newName: newName,
      ),
    );
  }

  /// Reorders folders from [oldIndex] to target [newIndex] and persists.
  Future<void> reorderFolders(int oldIndex, int newIndex) async {
    await _mutate(
      (current) =>
          LibraryOperations.reorderFolders(current, oldIndex, newIndex),
    );
  }

  /// Deletes [folderId] (optionally moving its pads to [movePadsToFolderId])
  /// and persists the library. Any deleted active pads are automatically
  /// stopped by [PlaybackController] observing library updates, and unreferenced
  /// private audio files are removed from disk.
  Future<void> deleteFolder(
    String folderId, {
    String? movePadsToFolderId,
  }) async {
    final before = state.asData?.value ?? await future;
    final after = await _mutate(
      (library) => LibraryOperations.deleteFolder(
        library,
        folderId: folderId,
        movePadsToFolderId: movePadsToFolderId,
      ),
    );
    if (movePadsToFolderId == null) {
      final deletedPaths = before.pads
          .where((pad) => pad.folderId == folderId && !pad.isAsset)
          .map((pad) => pad.audioPath)
          .toSet();
      await _deleteUnreferencedPrivateFiles(
        candidatePaths: deletedPaths,
        remainingLibrary: after,
      );
    }
  }

  /// Reorders pads within [folderId] and persists.
  Future<void> reorderPadsInFolder(
    String folderId,
    int oldIndex,
    int newIndex,
  ) async {
    await _mutate(
      (current) => LibraryOperations.reorderPadsInFolder(
        current,
        folderId: folderId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  /// Moves [padId] to the end of [targetFolderId] and persists.
  Future<void> movePadToFolder(String padId, String targetFolderId) async {
    await _mutate(
      (current) => LibraryOperations.movePadToFolder(
        current,
        padId: padId,
        targetFolderId: targetFolderId,
      ),
    );
  }

  /// Updates an existing pad and persists. [PlaybackController] automatically
  /// clears any playback error state if the pad's audio source changed.
  Future<void> updatePad(SoundPad updatedPad) async {
    await _mutate(
      (library) => LibraryOperations.updatePad(library, updatedPad),
    );
  }

  /// Removes [padId] from the library and persists. [PlaybackController]
  /// automatically stops playback if the deleted pad is currently active, and
  /// removes the private audio file if no remaining pad references it.
  Future<void> deletePad(String padId) async {
    final before = state.asData?.value ?? await future;
    SoundPad? deletedPad;
    for (final pad in before.pads) {
      if (pad.id == padId) {
        deletedPad = pad;
        break;
      }
    }
    final after = await _mutate(
      (current) => LibraryOperations.deletePad(current, padId),
    );
    if (deletedPad != null && !deletedPad.isAsset) {
      await _deleteUnreferencedPrivateFiles(
        candidatePaths: <String>{deletedPad.audioPath},
        remainingLibrary: after,
      );
    }
  }

  /// Appends [pads] to their respective folders and persists.
  Future<void> addPads(List<SoundPad> pads) async {
    await _mutate((current) => LibraryOperations.addPads(current, pads));
  }

  /// Imports user-selected [files] into app-private storage and appends new
  /// pads to [folderId]. Unsupported or unreadable files are skipped gracefully.
  Future<ImportAudioResult> importAudioFiles({
    required String folderId,
    required List<PickedAudioFile> files,
  }) async {
    if (files.isEmpty) {
      return const ImportAudioResult(
        importedCount: 0,
        skippedCount: 0,
        importedPads: <SoundPad>[],
      );
    }

    final current = state.asData?.value ?? await future;
    if (current.folders.isEmpty) {
      return ImportAudioResult(
        importedCount: 0,
        skippedCount: files.length,
        importedPads: const <SoundPad>[],
      );
    }

    final targetFolderId =
        current.folders.any((folder) => folder.id == folderId)
        ? folderId
        : current.folders.first.id;
    final store = ref.read(audioFileStoreProvider);

    final importedPads = <SoundPad>[];
    var skippedCount = 0;
    var colorIndex = current.pads.length;

    for (final file in files) {
      try {
        final String storedPath;
        final filePath = file.path;
        final fileBytes = file.bytes;
        if (filePath != null && filePath.isNotEmpty) {
          storedPath = await store.copyToPrivateStorage(
            sourcePath: filePath,
            originalFileName: file.name,
          );
        } else if (fileBytes != null) {
          storedPath = await store.writeBytesToPrivateStorage(
            bytes: fileBytes,
            originalFileName: file.name,
          );
        } else {
          skippedCount++;
          continue;
        }

        final labelSource = file.name.trim().isNotEmpty
            ? file.name
            : (filePath ?? '');
        final label = store.derivePadLabel(labelSource);
        final colorValue =
            _importedPadColorPalette[colorIndex %
                _importedPadColorPalette.length];
        colorIndex++;

        importedPads.add(
          SoundPad(
            id: 'pad_${_uuid.v4()}',
            folderId: targetFolderId,
            label: label,
            colorValue: colorValue,
            audioPath: storedPath,
            isAsset: false,
            type: PadType.effect,
            order: 0,
          ),
        );
      } catch (_) {
        skippedCount++;
      }
    }

    if (importedPads.isNotEmpty) {
      await _mutate(
        (library) => LibraryOperations.addPads(library, importedPads),
      );
    }

    return ImportAudioResult(
      importedCount: importedPads.length,
      skippedCount: skippedCount,
      importedPads: List<SoundPad>.unmodifiable(importedPads),
    );
  }

  /// Exports the current [SoundLibrary] and all non-asset audio files as a
  /// portable ZIP archive byte buffer.
  Future<Uint8List> exportBackup() async {
    final current = state.asData?.value ?? await future;
    return ref.read(backupServiceProvider).exportBackup(current);
  }

  /// Validates and imports a backup archive, persists it to storage, and
  /// replaces the current library state.
  ///
  /// Persists before mutating in-memory state and rolls back newly extracted
  /// audio files if persistence fails. Callers stop active playback via
  /// `playbackControllerProvider` after restore succeeds to preserve one-way
  /// Riverpod dependencies (`PlaybackController -> LibraryController`) and
  /// prevent invalid backups from disrupting live audio.
  Future<SoundLibrary> importBackup(Uint8List archiveBytes) async {
    final previous = state.asData?.value ?? await future;
    final restored = await ref
        .read(backupServiceProvider)
        .importBackup(archiveBytes);

    final oldPrivatePaths = previous.pads
        .where((pad) => !pad.isAsset)
        .map((pad) => pad.audioPath)
        .toSet();
    final newPrivatePaths = restored.pads
        .where((pad) => !pad.isAsset)
        .map((pad) => pad.audioPath)
        .toSet();

    try {
      await ref.read(libraryRepositoryProvider).save(restored);
    } catch (_) {
      await _deleteUnreferencedPrivateFiles(
        candidatePaths: newPrivatePaths,
        remainingLibrary: previous,
      );
      rethrow;
    }

    state = AsyncData<SoundLibrary>(restored);

    await _deleteUnreferencedPrivateFiles(
      candidatePaths: oldPrivatePaths,
      remainingLibrary: restored,
    );

    return restored;
  }

  Future<void> _deleteUnreferencedPrivateFiles({
    required Set<String> candidatePaths,
    required SoundLibrary remainingLibrary,
  }) async {
    if (candidatePaths.isEmpty) {
      return;
    }
    final remainingPaths = remainingLibrary.pads
        .where((pad) => !pad.isAsset)
        .map((pad) => pad.audioPath)
        .toSet();
    final store = ref.read(audioFileStoreProvider);
    for (final path in candidatePaths) {
      if (!remainingPaths.contains(path)) {
        await store.deletePrivateFile(path);
      }
    }
  }
}

/// Controls pad playback state transitions via [PlaybackEngine].
final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  late PlaybackEngine _engine;
  bool _initialized = false;
  Future<void>? _pendingInit;
  bool _disposed = false;

  @override
  PlaybackState build() {
    _initialized = false;
    _pendingInit = null;
    _disposed = false;

    final audioEngine = ref.read(audioEngineProvider);
    final clock = ref.read(clockProvider);
    final initialSettings =
        ref.read(libraryControllerProvider).asData?.value.settings ??
        const BoardSettings();

    var isBuildDisposed = false;
    late final PlaybackEngine engine;
    engine = PlaybackEngine(
      audioEngine: audioEngine,
      clock: clock,
      settings: initialSettings,
      onStateChanged: (nextState) {
        if (!isBuildDisposed) {
          state = nextState;
        }
      },
    );
    _engine = engine;

    ref.listen<AsyncValue<SoundLibrary>>(libraryControllerProvider, (
      previous,
      next,
    ) {
      if (isBuildDisposed) {
        return;
      }
      final prevLibrary = previous?.asData?.value;
      final nextLibrary = next.asData?.value;
      if (nextLibrary == null) {
        return;
      }

      if (nextLibrary.settings != prevLibrary?.settings &&
          nextLibrary.settings != engine.settings) {
        unawaited(engine.updateSettings(nextLibrary.settings));
      }

      if (prevLibrary != null) {
        final nextPadsById = <String, SoundPad>{
          for (final pad in nextLibrary.pads) pad.id: pad,
        };
        for (final prevPad in prevLibrary.pads) {
          final nextPad = nextPadsById[prevPad.id];
          if (nextPad == null) {
            unawaited(engine.stopPad(prevPad.id));
            engine.clearPadError(prevPad.id);
          } else if (nextPad.audioPath != prevPad.audioPath ||
              nextPad.isAsset != prevPad.isAsset) {
            engine.clearPadError(prevPad.id);
          }
        }
      }
    });

    ref.onDispose(() {
      isBuildDisposed = true;
      _disposed = true;
      unawaited(engine.dispose(disposeAudioEngine: false));
    });

    return engine.state;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _disposed) {
      return;
    }
    final pending = _pendingInit;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _engine.initialize();
    _pendingInit = future;
    try {
      await future;
      if (!_disposed) {
        _initialized = true;
      }
    } finally {
      if (identical(_pendingInit, future)) {
        _pendingInit = null;
      }
    }
  }

  Future<void> tapPad(SoundPad pad) async {
    await _ensureInitialized();
    await _engine.tapPad(pad);
  }

  Future<void> stopPad(String padId) async {
    await _engine.stopPad(padId);
  }

  Future<void> stopAll() async {
    await _engine.stopAll();
  }

  Future<void> setPadVolume(String padId, double volume) async {
    await _engine.setPadVolume(padId, volume);
  }

  Future<void> setMasterVolume(double volume) async {
    await _ensureInitialized();
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    await _engine.setMasterVolume(clamped);
    final currentLibrary = ref.read(libraryControllerProvider).asData?.value;
    if (currentLibrary != null &&
        currentLibrary.settings.masterVolume != clamped) {
      await ref
          .read(libraryControllerProvider.notifier)
          .updateSettings(
            currentLibrary.settings.copyWith(masterVolume: clamped),
          );
    }
  }

  Future<void> pauseForInterruption() async {
    await _engine.pauseForInterruption();
  }

  Future<void> resumeAfterInterruption() async {
    await _engine.resumeAfterInterruption();
  }

  void clearPadError(String padId) {
    _engine.clearPadError(padId);
  }
}
