import 'package:auraboard/domain/library_operations.dart';
import 'package:auraboard/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

SoundLibrary _sampleLibrary() {
  return const SoundLibrary(
    schemaVersion: 1,
    folders: <SoundFolder>[
      SoundFolder(id: 'f_combat', name: 'Combat', order: 0),
      SoundFolder(id: 'f_tavern', name: 'Tavern', order: 1),
      SoundFolder(id: 'f_dungeon', name: 'Dungeon', order: 2),
    ],
    pads: <SoundPad>[
      SoundPad(
        id: 'p_sword',
        folderId: 'f_combat',
        label: 'Sword Clash',
        colorValue: 0xFFB84A39,
        icon: PadIcon.sword,
        audioPath: 'assets/demo_audio/sword_clash.wav',
        isAsset: true,
        type: PadType.effect,
        order: 0,
      ),
      SoundPad(
        id: 'p_fireball',
        folderId: 'f_combat',
        label: 'Fireball',
        colorValue: 0xFFD96B27,
        icon: PadIcon.fire,
        audioPath: 'assets/demo_audio/fireball_boom.wav',
        isAsset: true,
        type: PadType.effect,
        order: 1,
      ),
      SoundPad(
        id: 'p_drums',
        folderId: 'f_combat',
        label: 'Battle Drums',
        colorValue: 0xFF9C3D3D,
        icon: PadIcon.drum,
        audioPath: 'assets/demo_audio/combat_drums_music.wav',
        isAsset: true,
        type: PadType.music,
        order: 2,
      ),
      SoundPad(
        id: 'p_hearth',
        folderId: 'f_tavern',
        label: 'Tavern Hearth',
        colorValue: 0xFFC68A32,
        icon: PadIcon.tavern,
        audioPath: 'assets/demo_audio/tavern_hearth_music.wav',
        isAsset: true,
        type: PadType.music,
        order: 0,
      ),
      SoundPad(
        id: 'p_rain',
        folderId: 'f_tavern',
        label: 'Steady Rain',
        colorValue: 0xFF3E6D8C,
        icon: PadIcon.rain,
        audioPath: 'assets/demo_audio/rain_ambience.wav',
        isAsset: true,
        type: PadType.ambience,
        order: 1,
      ),
      SoundPad(
        id: 'p_wind',
        folderId: 'f_dungeon',
        label: 'Dungeon Wind',
        colorValue: 0xFF4F5D75,
        icon: PadIcon.wind,
        audioPath: 'assets/demo_audio/dungeon_wind_ambience.wav',
        isAsset: true,
        type: PadType.ambience,
        order: 0,
      ),
    ],
    settings: BoardSettings(masterVolume: 0.85),
  );
}

List<SoundFolder> _sortedFolders(SoundLibrary library) {
  final list = List<SoundFolder>.from(library.folders)
    ..sort((a, b) => a.order.compareTo(b.order));
  return list;
}

List<SoundPad> _sortedPadsIn(SoundLibrary library, String folderId) {
  final list = library.pads.where((pad) => pad.folderId == folderId).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return list;
}

void main() {
  group('LibraryOperations.createFolder', () {
    test(
      'trims name, appends folder with next order, and preserves immutability',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.createFolder(
          initial,
          id: 'f_boss',
          name: '  Boss Fight  ',
        );

        expect(initial.folders, hasLength(3));
        final folders = _sortedFolders(updated);
        expect(folders, hasLength(4));
        expect(folders.last.id, 'f_boss');
        expect(folders.last.name, 'Boss Fight');
        expect(folders.last.order, 3);
        expect(folders.map((f) => f.order).toList(), <int>[0, 1, 2, 3]);
        expect(updated.pads, equals(initial.pads));
        expect(updated.settings, equals(initial.settings));
      },
    );

    test('creates first folder with order 0 when library has no folders', () {
      const empty = SoundLibrary(folders: <SoundFolder>[], pads: <SoundPad>[]);

      final updated = LibraryOperations.createFolder(
        empty,
        id: 'f_first',
        name: 'Session 1',
      );

      expect(updated.folders, hasLength(1));
      expect(updated.folders.single.id, 'f_first');
      expect(updated.folders.single.name, 'Session 1');
      expect(updated.folders.single.order, 0);
    });

    test('throws ArgumentError on empty or whitespace-only name', () {
      final initial = _sampleLibrary();

      expect(
        () => LibraryOperations.createFolder(initial, id: 'f_empty', name: ''),
        throwsArgumentError,
      );
      expect(
        () => LibraryOperations.createFolder(
          initial,
          id: 'f_spaces',
          name: '   \t\n  ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('LibraryOperations.renameFolder', () {
    test('trims newName and updates only the matching folder', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.renameFolder(
        initial,
        folderId: 'f_tavern',
        newName: '  Dragon Inn  ',
      );

      final folders = _sortedFolders(updated);
      expect(folders.map((f) => f.id).toList(), <String>[
        'f_combat',
        'f_tavern',
        'f_dungeon',
      ]);
      expect(folders.map((f) => f.name).toList(), <String>[
        'Combat',
        'Dragon Inn',
        'Dungeon',
      ]);
      expect(folders.map((f) => f.order).toList(), <int>[0, 1, 2]);
      expect(updated.pads, equals(initial.pads));
      expect(updated.settings, equals(initial.settings));
    });

    test('throws ArgumentError on empty or whitespace-only newName', () {
      final initial = _sampleLibrary();

      expect(
        () => LibraryOperations.renameFolder(
          initial,
          folderId: 'f_combat',
          newName: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => LibraryOperations.renameFolder(
          initial,
          folderId: 'f_combat',
          newName: '   \n\t ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('LibraryOperations.reorderFolders', () {
    test('handles forward move and normalizes orders 0..n-1', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.reorderFolders(initial, 0, 2);
      final folders = _sortedFolders(updated);

      expect(folders.map((f) => f.id).toList(), <String>[
        'f_tavern',
        'f_dungeon',
        'f_combat',
      ]);
      expect(folders.map((f) => f.order).toList(), <int>[0, 1, 2]);
    });

    test('handles backward move and normalizes orders 0..n-1', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.reorderFolders(initial, 2, 0);
      final folders = _sortedFolders(updated);

      expect(folders.map((f) => f.id).toList(), <String>[
        'f_dungeon',
        'f_combat',
        'f_tavern',
      ]);
      expect(folders.map((f) => f.order).toList(), <int>[0, 1, 2]);
    });

    test(
      'sorts by existing order before applying indices and normalizes gaps',
      () {
        final unsorted = _sampleLibrary().copyWith(
          folders: const <SoundFolder>[
            SoundFolder(id: 'f_dungeon', name: 'Dungeon', order: 20),
            SoundFolder(id: 'f_combat', name: 'Combat', order: 5),
            SoundFolder(id: 'f_tavern', name: 'Tavern', order: 10),
          ],
        );

        final updated = LibraryOperations.reorderFolders(unsorted, 1, 0);
        final folders = _sortedFolders(updated);

        expect(folders.map((f) => f.id).toList(), <String>[
          'f_tavern',
          'f_combat',
          'f_dungeon',
        ]);
        expect(folders.map((f) => f.order).toList(), <int>[0, 1, 2]);
      },
    );
  });

  group('LibraryOperations.deleteFolder', () {
    test('throws StateError when deleting the last remaining folder', () {
      const singleFolder = SoundLibrary(
        folders: <SoundFolder>[
          SoundFolder(id: 'f_only', name: 'Only Folder', order: 0),
        ],
        pads: <SoundPad>[],
      );

      expect(
        () => LibraryOperations.deleteFolder(singleFolder, folderId: 'f_only'),
        throwsStateError,
      );
    });

    test(
      'removes folder and its pads when movePadsToFolderId is null and normalizes remaining folders',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.deleteFolder(
          initial,
          folderId: 'f_combat',
        );

        final folders = _sortedFolders(updated);
        expect(folders.map((f) => f.id).toList(), <String>[
          'f_tavern',
          'f_dungeon',
        ]);
        expect(folders.map((f) => f.order).toList(), <int>[0, 1]);

        expect(updated.pads.where((p) => p.folderId == 'f_combat'), isEmpty);
        expect(
          _sortedPadsIn(updated, 'f_tavern').map((p) => p.id).toList(),
          <String>['p_hearth', 'p_rain'],
        );
        expect(
          _sortedPadsIn(updated, 'f_dungeon').map((p) => p.id).toList(),
          <String>['p_wind'],
        );
      },
    );

    test(
      'moves orphaned pads to movePadsToFolderId and normalizes pad and folder orders',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.deleteFolder(
          initial,
          folderId: 'f_combat',
          movePadsToFolderId: 'f_tavern',
        );

        final folders = _sortedFolders(updated);
        expect(folders.map((f) => f.id).toList(), <String>[
          'f_tavern',
          'f_dungeon',
        ]);
        expect(folders.map((f) => f.order).toList(), <int>[0, 1]);

        final tavernPads = _sortedPadsIn(updated, 'f_tavern');
        expect(tavernPads.map((p) => p.id).toList(), <String>[
          'p_hearth',
          'p_rain',
          'p_sword',
          'p_fireball',
          'p_drums',
        ]);
        expect(tavernPads.map((p) => p.order).toList(), <int>[0, 1, 2, 3, 4]);
        expect(tavernPads.every((p) => p.folderId == 'f_tavern'), isTrue);
        expect(
          _sortedPadsIn(updated, 'f_dungeon').map((p) => p.id).toList(),
          <String>['p_wind'],
        );
      },
    );
  });

  group('LibraryOperations.reorderPadsInFolder', () {
    test(
      'forward move reorders only target folder pads and leaves other folders untouched',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.reorderPadsInFolder(
          initial,
          folderId: 'f_combat',
          oldIndex: 0,
          newIndex: 2,
        );

        final combatPads = _sortedPadsIn(updated, 'f_combat');
        expect(combatPads.map((p) => p.id).toList(), <String>[
          'p_fireball',
          'p_drums',
          'p_sword',
        ]);
        expect(combatPads.map((p) => p.order).toList(), <int>[0, 1, 2]);

        expect(
          _sortedPadsIn(updated, 'f_tavern'),
          equals(_sortedPadsIn(initial, 'f_tavern')),
        );
        expect(
          _sortedPadsIn(updated, 'f_dungeon'),
          equals(_sortedPadsIn(initial, 'f_dungeon')),
        );
      },
    );

    test(
      'backward move reorders only target folder pads and normalizes orders',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.reorderPadsInFolder(
          initial,
          folderId: 'f_combat',
          oldIndex: 2,
          newIndex: 0,
        );

        final combatPads = _sortedPadsIn(updated, 'f_combat');
        expect(combatPads.map((p) => p.id).toList(), <String>[
          'p_drums',
          'p_sword',
          'p_fireball',
        ]);
        expect(combatPads.map((p) => p.order).toList(), <int>[0, 1, 2]);
      },
    );
  });

  group('LibraryOperations.movePadToFolder', () {
    test(
      'moves pad to end of target folder and normalizes both source and target orders',
      () {
        final initial = _sampleLibrary();

        final updated = LibraryOperations.movePadToFolder(
          initial,
          padId: 'p_sword',
          targetFolderId: 'f_tavern',
        );

        final combatPads = _sortedPadsIn(updated, 'f_combat');
        expect(combatPads.map((p) => p.id).toList(), <String>[
          'p_fireball',
          'p_drums',
        ]);
        expect(combatPads.map((p) => p.order).toList(), <int>[0, 1]);

        final tavernPads = _sortedPadsIn(updated, 'f_tavern');
        expect(tavernPads.map((p) => p.id).toList(), <String>[
          'p_hearth',
          'p_rain',
          'p_sword',
        ]);
        expect(tavernPads.map((p) => p.order).toList(), <int>[0, 1, 2]);
        expect(tavernPads.last.folderId, 'f_tavern');

        expect(
          _sortedPadsIn(updated, 'f_dungeon'),
          equals(_sortedPadsIn(initial, 'f_dungeon')),
        );
      },
    );

    test('is a no-op when pad is already in targetFolderId', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.movePadToFolder(
        initial,
        padId: 'p_fireball',
        targetFolderId: 'f_combat',
      );

      expect(updated, equals(initial));
    });

    test('throws ArgumentError when targetFolderId does not exist', () {
      final initial = _sampleLibrary();

      expect(
        () => LibraryOperations.movePadToFolder(
          initial,
          padId: 'p_sword',
          targetFolderId: 'f_missing',
        ),
        throwsArgumentError,
      );
    });
  });

  group('LibraryOperations.updatePad', () {
    test(
      'replaces matching pad by id cleanly without affecting other pads',
      () {
        final initial = _sampleLibrary();
        final originalSword = initial.pads.firstWhere((p) => p.id == 'p_sword');
        final editedSword = originalSword.copyWith(
          label: 'Vorpal Blade',
          colorValue: 0xFF6A4C93,
          icon: PadIcon.magic,
          volume: 0.7,
          retriggerMode: RetriggerMode.layer,
          fadeOutMsOverride: 250,
        );

        final updated = LibraryOperations.updatePad(initial, editedSword);

        expect(updated.pads, hasLength(initial.pads.length));
        final stored = updated.pads.firstWhere((p) => p.id == 'p_sword');
        expect(stored, equals(editedSword));

        final otherInitial = initial.pads
            .where((p) => p.id != 'p_sword')
            .toList();
        final otherUpdated = updated.pads
            .where((p) => p.id != 'p_sword')
            .toList();
        expect(otherUpdated, equals(otherInitial));
      },
    );
  });

  group('LibraryOperations.deletePad', () {
    test('removes pad and normalizes remaining pad orders in its folder', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.deletePad(initial, 'p_sword');

      expect(updated.pads.any((p) => p.id == 'p_sword'), isFalse);

      final combatPads = _sortedPadsIn(updated, 'f_combat');
      expect(combatPads.map((p) => p.id).toList(), <String>[
        'p_fireball',
        'p_drums',
      ]);
      expect(combatPads.map((p) => p.order).toList(), <int>[0, 1]);

      expect(
        _sortedPadsIn(updated, 'f_tavern'),
        equals(_sortedPadsIn(initial, 'f_tavern')),
      );
      expect(
        _sortedPadsIn(updated, 'f_dungeon'),
        equals(_sortedPadsIn(initial, 'f_dungeon')),
      );
    });
  });

  group('LibraryOperations.addPads', () {
    test(
      'appends new pads with sequential order in their respective target folders',
      () {
        final initial = LibraryOperations.createFolder(
          _sampleLibrary(),
          id: 'f_empty',
          name: 'Empty',
        );

        const additions = <SoundPad>[
          SoundPad(
            id: 'p_arrow',
            folderId: 'f_combat',
            label: 'Arrow Volley',
            colorValue: 0xFF556B2F,
            icon: PadIcon.bolt,
            audioPath: '/audio/arrow.wav',
            type: PadType.effect,
            order: 99,
          ),
          SoundPad(
            id: 'p_shield',
            folderId: 'f_combat',
            label: 'Shield Bash',
            colorValue: 0xFF4682B4,
            icon: PadIcon.shield,
            audioPath: '/audio/shield.wav',
            type: PadType.effect,
            order: 0,
          ),
          SoundPad(
            id: 'p_roar',
            folderId: 'f_empty',
            label: 'Dragon Roar',
            colorValue: 0xFF8B0000,
            icon: PadIcon.monster,
            audioPath: '/audio/roar.wav',
            type: PadType.effect,
            order: 42,
          ),
        ];

        final updated = LibraryOperations.addPads(initial, additions);

        final combatPads = _sortedPadsIn(updated, 'f_combat');
        expect(combatPads.map((p) => p.id).toList(), <String>[
          'p_sword',
          'p_fireball',
          'p_drums',
          'p_arrow',
          'p_shield',
        ]);
        expect(combatPads.map((p) => p.order).toList(), <int>[0, 1, 2, 3, 4]);

        final emptyFolderPads = _sortedPadsIn(updated, 'f_empty');
        expect(emptyFolderPads.map((p) => p.id).toList(), <String>['p_roar']);
        expect(emptyFolderPads.map((p) => p.order).toList(), <int>[0]);
      },
    );

    test('empty list is a clean no-op', () {
      final initial = _sampleLibrary();

      final updated = LibraryOperations.addPads(initial, const <SoundPad>[]);

      expect(updated, equals(initial));
    });
  });
}
