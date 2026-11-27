import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryLibraryRepository & Demo seeding', () {
    test(
      'seeds demo board with Combat, Tavern, Dungeon folders on first load',
      () async {
        final repo = InMemoryLibraryRepository();
        final library = await repo.load();

        expect(
          library.folders.map((f) => f.name),
          containsAll(['Combat', 'Tavern', 'Dungeon']),
        );
        expect(
          library.pads.any(
            (p) => p.label == 'Sword Clash' && p.type == PadType.effect,
          ),
          isTrue,
        );
        expect(library.pads.any((p) => p.type == PadType.music), isTrue);
        expect(library.pads.any((p) => p.type == PadType.ambience), isTrue);
      },
    );

    test('persists saved library across subsequent loads', () async {
      final repo = InMemoryLibraryRepository();
      final initial = await repo.load();
      final updated = initial.copyWith(
        settings: initial.settings.copyWith(masterVolume: 0.5),
      );
      await repo.save(updated);

      final reloaded = await repo.load();
      expect(reloaded.settings.masterVolume, 0.5);
    });
  });
}
