import 'dart:async';

import 'package:auraboard/audio/soloud_audio_engine.dart';
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
  /// stopped by [PlaybackController] observing library updates.
  Future<void> deleteFolder(
    String folderId, {
    String? movePadsToFolderId,
  }) async {
    await _mutate(
      (library) => LibraryOperations.deleteFolder(
        library,
        folderId: folderId,
        movePadsToFolderId: movePadsToFolderId,
      ),
    );
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
  /// automatically stops playback if the deleted pad is currently active.
  Future<void> deletePad(String padId) async {
    await _mutate((current) => LibraryOperations.deletePad(current, padId));
  }

  /// Appends [pads] to their respective folders and persists.
  Future<void> addPads(List<SoundPad> pads) async {
    await _mutate((current) => LibraryOperations.addPads(current, pads));
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
