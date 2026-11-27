import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

void main() {
  test(
    'ProviderScope plays/stops an effect via stopPad and toggles looping music',
    () async {
      final engine = FakeAudioEngine();
      final clock = FakeClock();
      final repo = InMemoryLibraryRepository();

      final container = ProviderContainer(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          clockProvider.overrideWithValue(clock),
          libraryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final library = await container.read(libraryControllerProvider.future);
      final swordPad = library.pads.firstWhere((p) => p.label == 'Sword Clash');
      final musicPad = library.pads.firstWhere(
        (p) => p.label == 'Battle Drums',
      );

      final playback = container.read(playbackControllerProvider.notifier);

      // Effect starts immediately and stops cleanly via stopPad.
      await playback.tapPad(swordPad);
      expect(engine.playedHandles, hasLength(1));
      expect(
        container.read(playbackControllerProvider).phaseForPad(swordPad.id),
        PadPlaybackPhase.playing,
      );

      await playback.stopPad(swordPad.id);
      expect(engine.stoppedHandles, contains(engine.playedHandles.first));
      expect(
        container.read(playbackControllerProvider).phaseForPad(swordPad.id),
        PadPlaybackPhase.idle,
      );

      // Music fades in on tap and fades out on second tap.
      await playback.tapPad(musicPad);
      expect(
        container.read(playbackControllerProvider).phaseForPad(musicPad.id),
        PadPlaybackPhase.fadingIn,
      );
      clock.advance(const Duration(seconds: 2));
      expect(
        container.read(playbackControllerProvider).phaseForPad(musicPad.id),
        PadPlaybackPhase.playing,
      );

      await playback.tapPad(musicPad);
      expect(
        container.read(playbackControllerProvider).phaseForPad(musicPad.id),
        PadPlaybackPhase.fadingOut,
      );
      clock.advance(const Duration(seconds: 3));
      expect(
        container.read(playbackControllerProvider).phaseForPad(musicPad.id),
        PadPlaybackPhase.idle,
      );
    },
  );

  test('ProviderScope surfaces AudioLoadException as error phase', () async {
    final repo = InMemoryLibraryRepository();
    final initial = await repo.load();
    final swordPad = initial.pads.firstWhere((p) => p.label == 'Sword Clash');
    final engine = FakeAudioEngine(failingPaths: {swordPad.audioPath});
    final clock = FakeClock();

    final container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        clockProvider.overrideWithValue(clock),
        libraryRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    final playback = container.read(playbackControllerProvider.notifier);
    await playback.tapPad(swordPad);

    expect(
      container.read(playbackControllerProvider).phaseForPad(swordPad.id),
      PadPlaybackPhase.error,
    );
  });
}
