import 'package:auraboard/app.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_audio_engine.dart';
import 'helpers/fake_clock.dart';

void main() {
  testWidgets(
    'launches AuraBoard, loads demo Combat board, plays and stops Sword Clash',
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
        //    Combat folder and demo pad Sword Clash.
        expect(find.text('Combat'), findsWidgets);
        expect(find.text('Sword Clash'), findsOneWidget);

        // c) Tapping Sword Clash starts playback and updates visual + semantic
        //    active state unmistakably.
        await tester.tap(find.text('Sword Clash'));
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
              r'Sword Clash.*(Playing|Fading in)',
              caseSensitive: false,
              dotAll: true,
            ),
          ),
          findsOneWidget,
        );

        // d) Tapping Sword Clash a second time stops playback (completing any
        //    fade-out via FakeClock) and returns the pad to idle state.
        await tester.tap(find.text('Sword Clash'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        if (!fakeEngine.stoppedHandles.contains(handle)) {
          fakeClock.advance(const Duration(seconds: 5));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(fakeEngine.stoppedHandles, contains(handle));
        expect(
          find.textContaining(
            RegExp(r'Playing|Fading in', caseSensitive: false),
          ),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              r'Sword Clash.*(Playing|Fading in|Fading out)',
              caseSensitive: false,
              dotAll: true,
            ),
          ),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Sword Clash.*Idle', caseSensitive: false, dotAll: true),
          ),
          findsOneWidget,
        );
      } finally {
        semanticsHandle.dispose();
      }
    },
  );
}
