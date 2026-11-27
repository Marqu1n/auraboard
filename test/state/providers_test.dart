import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

void main() {
  test(
    'ProviderScope initializes library and plays/stops a demo pad',
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

      final playback = container.read(playbackControllerProvider.notifier);
      await playback.tapPad(swordPad);
      expect(engine.playedHandles, hasLength(1));
      expect(
        container.read(playbackControllerProvider).phaseForPad(swordPad.id),
        PadPlaybackPhase.playing,
      );

      await playback.tapPad(swordPad);
      expect(engine.stoppedHandles, contains(engine.playedHandles.single));
      expect(
        container.read(playbackControllerProvider).phaseForPad(swordPad.id),
        PadPlaybackPhase.idle,
      );
    },
  );
}
