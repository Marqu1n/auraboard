import 'package:auraboard/app.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_audio_engine.dart';
import 'helpers/fake_clock.dart';

void main() {
  testWidgets(
    'launches AuraBoard, loads demo Combat board, plays and stops Battle Drums',
    (WidgetTester tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              audioEngineProvider.overrideWithValue(fakeEngine),
              clockProvider.overrideWithValue(fakeClock),
              libraryRepositoryProvider.overrideWithValue(repository),
            ],
            child: const AuraBoardApp(),
          ),
        );
        await tester.pumpAndSettle();

        // a) App launches and displays AuraBoard title.
        expect(find.text('AuraBoard'), findsOneWidget);

        // b) Demo library loads automatically on first run and displays the
        //    Combat folder and demo pads.
        expect(find.text('Combat'), findsWidgets);
        expect(find.text('Sword Clash'), findsOneWidget);
        expect(find.text('Battle Drums'), findsOneWidget);

        // c) Tapping Battle Drums starts playback (fading in -> playing) and
        //    updates visual + semantic active state unmistakably.
        await tester.tap(find.text('Battle Drums'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(fakeEngine.playedHandles, hasLength(1));
        final handle = fakeEngine.playedHandles.single;

        expect(
          find.textContaining(
            RegExp(r'Playing|Fading in', caseSensitive: false),
          ),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              r'Battle Drums.*(Playing|Fading in)',
              caseSensitive: false,
              dotAll: true,
            ),
          ),
          findsOneWidget,
        );

        // Complete fade-in via FakeClock -> Playing.
        fakeClock.advance(const Duration(seconds: 2));
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            RegExp(
              r'Battle Drums.*Playing',
              caseSensitive: false,
              dotAll: true,
            ),
          ),
          findsOneWidget,
        );

        // d) Tapping Battle Drums a second time fades out smoothly and stops
        //    playback, returning the pad to idle state.
        await tester.tap(find.text('Battle Drums'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.bySemanticsLabel(
            RegExp(
              r'Battle Drums.*Fading out',
              caseSensitive: false,
              dotAll: true,
            ),
          ),
          findsOneWidget,
        );

        fakeClock.advance(const Duration(seconds: 5));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(fakeEngine.stoppedHandles, contains(handle));
        expect(
          find.textContaining(
            RegExp(r'Playing|Fading in|Fading out', caseSensitive: false),
          ),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Battle Drums.*Idle', caseSensitive: false, dotAll: true),
          ),
          findsOneWidget,
        );
      } finally {
        semanticsHandle.dispose();
      }
    },
  );
}
