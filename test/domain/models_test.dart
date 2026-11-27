import 'package:auraboard/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Domain models JSON round-trip', () {
    test('SoundLibrary serializes and deserializes losslessly', () {
      const folder = SoundFolder(id: 'f1', name: 'Combat', order: 0);
      const pad = SoundPad(
        id: 'p1',
        folderId: 'f1',
        label: 'Sword Clash',
        colorValue: 0xFFB84A39,
        icon: PadIcon.sword,
        audioPath: 'assets/demo_audio/sword_clash.wav',
        isAsset: true,
        type: PadType.effect,
        volume: 0.85,
        retriggerMode: RetriggerMode.layer,
        fadeInMsOverride: 250,
        fadeOutMsOverride: 400,
        crossfadeMsOverride: 1500,
        order: 0,
      );
      const settings = BoardSettings(
        defaultFadeInMs: 600,
        defaultFadeOutMs: 1100,
        defaultCrossfadeMs: 2200,
        masterVolume: 0.9,
        keepScreenAwake: true,
        gridDensity: GridDensity.compact,
        themeMode: AppThemeMode.light,
        seedColorValue: 0xFFD4882A,
        useDynamicColor: false,
      );
      const library = SoundLibrary(
        schemaVersion: 1,
        folders: [folder],
        pads: [pad],
        settings: settings,
      );

      final roundTripped = SoundLibrary.fromJson(library.toJson());
      expect(roundTripped, equals(library));
    });
  });
}
