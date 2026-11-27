import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:auraboard/data/audio_file_store.dart';
import 'package:auraboard/data/backup_service.dart';
import 'package:auraboard/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Directory _createTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

Uint8List _encodeZipEntries(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, data) {
    archive.addFile(ArchiveFile.bytes(name, data));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('BackupService', () {
    test(
      'full round-trip from device A to device B preserves folders, settings, metadata, asset pads, and non-asset audio bytes independently',
      () async {
        final deviceADir = _createTempDir('auraboard_backup_device_a_');
        final deviceBDir = _createTempDir('auraboard_backup_device_b_');

        final storeA = AudioFileStore(baseDirectory: deviceADir);
        final backupA = BackupService(audioFileStore: storeA);

        final wavBytes = File(
          'test/fixtures/sample_effect.wav',
        ).readAsBytesSync();
        final mp3Bytes = Uint8List.fromList(<int>[
          0x49,
          0x44,
          0x33,
          0x03,
          11,
          22,
          33,
        ]);
        final oggBytes = Uint8List.fromList(<int>[
          0x4F,
          0x67,
          0x67,
          0x53,
          44,
          55,
          66,
        ]);
        final flacBytes = Uint8List.fromList(<int>[
          0x66,
          0x4C,
          0x61,
          0x43,
          77,
          88,
          99,
        ]);
        final m4aBytes = Uint8List.fromList(<int>[
          0x00,
          0x00,
          0x00,
          0x20,
          0x66,
          0x74,
          0x79,
          0x70,
        ]);

        final wavPathA = await storeA.writeBytesToPrivateStorage(
          bytes: wavBytes,
          originalFileName: 'goblin_laugh.wav',
        );
        final mp3PathA = await storeA.writeBytesToPrivateStorage(
          bytes: mp3Bytes,
          originalFileName: 'dragon_boss.mp3',
        );
        final oggPathA = await storeA.writeBytesToPrivateStorage(
          bytes: oggBytes,
          originalFileName: 'tavern_rain.ogg',
        );
        final flacPathA = await storeA.writeBytesToPrivateStorage(
          bytes: flacBytes,
          originalFileName: 'dungeon_wind.flac',
        );
        final m4aPathA = await storeA.writeBytesToPrivateStorage(
          bytes: m4aBytes,
          originalFileName: 'victory_horn.m4a',
        );

        final expectedBytesByPadId = <String, Uint8List>{
          'pad_wav': wavBytes,
          'pad_mp3': mp3Bytes,
          'pad_ogg': oggBytes,
          'pad_flac': flacBytes,
          'pad_m4a': m4aBytes,
        };

        final libraryA = SoundLibrary(
          schemaVersion: 1,
          folders: const <SoundFolder>[
            SoundFolder(id: 'folder_combat', name: 'Combat', order: 0),
            SoundFolder(id: 'folder_boss', name: 'Boss Encounters', order: 1),
          ],
          pads: <SoundPad>[
            const SoundPad(
              id: 'pad_demo_asset',
              folderId: 'folder_combat',
              label: 'Sword Clash',
              colorValue: 0xFFC43B3B,
              icon: PadIcon.sword,
              audioPath: 'assets/demo_audio/sword_clash.wav',
              isAsset: true,
              type: PadType.effect,
              volume: 0.9,
              retriggerMode: RetriggerMode.restart,
              order: 0,
            ),
            SoundPad(
              id: 'pad_wav',
              folderId: 'folder_combat',
              label: 'Goblin Laugh',
              colorValue: 0xFF3A7D44,
              icon: PadIcon.monster,
              audioPath: wavPathA,
              isAsset: false,
              type: PadType.effect,
              volume: 0.85,
              retriggerMode: RetriggerMode.layer,
              fadeInMsOverride: 100,
              fadeOutMsOverride: 250,
              order: 1,
            ),
            SoundPad(
              id: 'pad_mp3',
              folderId: 'folder_boss',
              label: 'Dragon Boss',
              colorValue: 0xFFD4882A,
              icon: PadIcon.fire,
              audioPath: mp3PathA,
              isAsset: false,
              type: PadType.music,
              volume: 0.75,
              fadeInMsOverride: 400,
              fadeOutMsOverride: 900,
              crossfadeMsOverride: 1800,
              order: 0,
            ),
            SoundPad(
              id: 'pad_ogg',
              folderId: 'folder_boss',
              label: 'Tavern Rain',
              colorValue: 0xFF2B6CB0,
              icon: PadIcon.rain,
              audioPath: oggPathA,
              isAsset: false,
              type: PadType.ambience,
              volume: 0.65,
              order: 1,
            ),
            SoundPad(
              id: 'pad_flac',
              folderId: 'folder_boss',
              label: 'Dungeon Wind',
              colorValue: 0xFF6A4C93,
              icon: PadIcon.wind,
              audioPath: flacPathA,
              isAsset: false,
              type: PadType.ambience,
              volume: 0.55,
              order: 2,
            ),
            SoundPad(
              id: 'pad_m4a',
              folderId: 'folder_boss',
              label: 'Victory Horn',
              colorValue: 0xFFE07A5F,
              icon: PadIcon.bell,
              audioPath: m4aPathA,
              isAsset: false,
              type: PadType.effect,
              volume: 0.95,
              order: 3,
            ),
          ],
          settings: const BoardSettings(
            defaultFadeInMs: 350,
            defaultFadeOutMs: 1200,
            defaultCrossfadeMs: 2400,
            masterVolume: 0.72,
            keepScreenAwake: true,
            gridDensity: GridDensity.compact,
            themeMode: AppThemeMode.light,
            seedColorValue: 0xFF3A7D44,
            useDynamicColor: false,
          ),
        );

        final zipBytes = await backupA.exportBackup(libraryA);
        expect(zipBytes, isNotEmpty);

        // Verify portable ZIP layout (manifest.json + audio/<file> entries).
        final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
        final entryNames = decodedArchive.files.map((f) => f.name).toSet();
        expect(entryNames, contains('manifest.json'));
        expect(
          entryNames.where((name) => name.startsWith('audio/')).length,
          equals(5),
        );

        final manifestEntry = decodedArchive.findFile('manifest.json')!;
        final manifestJson =
            jsonDecode(utf8.decode(manifestEntry.content as List<int>))
                as Map<String, dynamic>;
        final manifestPads = (manifestJson['pads'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final padJson in manifestPads) {
          final isAsset = padJson['isAsset'] as bool? ?? false;
          final storedPath = padJson['audioPath'] as String;
          if (isAsset) {
            expect(storedPath, 'assets/demo_audio/sword_clash.wav');
          } else {
            expect(
              storedPath.startsWith('audio/'),
              isTrue,
              reason:
                  'Manifest should store portable relative audio/<file> paths, got $storedPath',
            );
            expect(storedPath.contains(deviceADir.path), isFalse);
          }
        }

        // Completely delete device A's storage before importing on device B.
        deviceADir.deleteSync(recursive: true);
        expect(deviceADir.existsSync(), isFalse);

        final storeB = AudioFileStore(baseDirectory: deviceBDir);
        final backupB = BackupService(audioFileStore: storeB);
        final restored = await backupB.importBackup(zipBytes);

        expect(restored.schemaVersion, equals(libraryA.schemaVersion));
        expect(restored.folders, equals(libraryA.folders));
        expect(restored.settings, equals(libraryA.settings));
        expect(restored.pads.length, equals(libraryA.pads.length));

        for (final originalPad in libraryA.pads) {
          final restoredPad = restored.pads.firstWhere(
            (pad) => pad.id == originalPad.id,
          );
          expect(restoredPad.folderId, originalPad.folderId);
          expect(restoredPad.label, originalPad.label);
          expect(restoredPad.colorValue, originalPad.colorValue);
          expect(restoredPad.icon, originalPad.icon);
          expect(restoredPad.isAsset, originalPad.isAsset);
          expect(restoredPad.type, originalPad.type);
          expect(restoredPad.volume, closeTo(originalPad.volume, 1e-9));
          expect(restoredPad.retriggerMode, originalPad.retriggerMode);
          expect(restoredPad.fadeInMsOverride, originalPad.fadeInMsOverride);
          expect(restoredPad.fadeOutMsOverride, originalPad.fadeOutMsOverride);
          expect(
            restoredPad.crossfadeMsOverride,
            originalPad.crossfadeMsOverride,
          );
          expect(restoredPad.order, originalPad.order);

          if (originalPad.isAsset) {
            expect(restoredPad.audioPath, originalPad.audioPath);
          } else {
            expect(
              p.isWithin(storeB.audioDirectory.path, restoredPad.audioPath),
              isTrue,
              reason:
                  'Restored audio file must live inside device B audioDirectory',
            );
            expect(restoredPad.audioPath.contains(deviceADir.path), isFalse);
            final restoredFile = File(restoredPad.audioPath);
            expect(restoredFile.existsSync(), isTrue);
            expect(
              restoredFile.readAsBytesSync(),
              equals(expectedBytesByPadId[originalPad.id]),
            );
          }
        }
      },
    );

    test('rejects corrupt and non-ZIP bytes with BackupException', () async {
      final dir = _createTempDir('auraboard_backup_corrupt_');
      final service = BackupService(
        audioFileStore: AudioFileStore(baseDirectory: dir),
      );

      await expectLater(
        () => service.importBackup(
          Uint8List.fromList(utf8.encode('definitely not a zip file')),
        ),
        throwsA(isA<BackupException>()),
      );

      await expectLater(
        () => service.importBackup(Uint8List(0)),
        throwsA(isA<BackupException>()),
      );
    });

    test(
      'rejects ZIP missing manifest.json or containing malformed manifest JSON',
      () async {
        final dir = _createTempDir('auraboard_backup_manifest_');
        final service = BackupService(
          audioFileStore: AudioFileStore(baseDirectory: dir),
        );

        final missingManifestZip = _encodeZipEntries(<String, List<int>>{
          'audio/sound.wav': <int>[1, 2, 3, 4],
        });
        await expectLater(
          () => service.importBackup(missingManifestZip),
          throwsA(isA<BackupException>()),
        );

        final brokenJsonZip = _encodeZipEntries(<String, List<int>>{
          'manifest.json': utf8.encode('{unterminated json'),
        });
        await expectLater(
          () => service.importBackup(brokenJsonZip),
          throwsA(isA<BackupException>()),
        );

        final badSchemaZip = _encodeZipEntries(<String, List<int>>{
          'manifest.json': utf8.encode(
            '{"schemaVersion": 1, "folders": "invalid"}',
          ),
        });
        await expectLater(
          () => service.importBackup(badSchemaZip),
          throwsA(isA<BackupException>()),
        );
      },
    );

    test(
      'rejects malicious ZIP with path-traversal entry without writing outside target directory',
      () async {
        final parentDir = _createTempDir('auraboard_backup_traversal_parent_');
        final deviceBDir = Directory(p.join(parentDir.path, 'device_b'))
          ..createSync(recursive: true);
        final storeB = AudioFileStore(baseDirectory: deviceBDir);
        final service = BackupService(audioFileStore: storeB);

        const minimalManifest = SoundLibrary(
          folders: <SoundFolder>[
            SoundFolder(id: 'f1', name: 'Combat', order: 0),
          ],
          pads: <SoundPad>[],
        );

        final evilZip = _encodeZipEntries(<String, List<int>>{
          'manifest.json': utf8.encode(jsonEncode(minimalManifest.toJson())),
          '../evil.wav': <int>[0xDE, 0xAD, 0xBE, 0xEF],
        });

        await expectLater(
          () => service.importBackup(evilZip),
          throwsA(isA<BackupException>()),
        );

        expect(File(p.join(parentDir.path, 'evil.wav')).existsSync(), isFalse);
        expect(File(p.join(deviceBDir.path, 'evil.wav')).existsSync(), isFalse);

        final nestedTraversalZip = _encodeZipEntries(<String, List<int>>{
          'manifest.json': utf8.encode(jsonEncode(minimalManifest.toJson())),
          'audio/../../escaped.wav': <int>[1, 2, 3, 4],
        });

        await expectLater(
          () => service.importBackup(nestedTraversalZip),
          throwsA(isA<BackupException>()),
        );

        expect(
          File(p.join(parentDir.path, 'escaped.wav')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(deviceBDir.path, 'escaped.wav')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'rolls back extracted audio files when archive is missing a referenced audio entry',
      () async {
        final deviceBDir = _createTempDir('auraboard_backup_rollback_');
        final storeB = AudioFileStore(baseDirectory: deviceBDir);
        final service = BackupService(audioFileStore: storeB);

        const partialManifest = SoundLibrary(
          folders: <SoundFolder>[
            SoundFolder(id: 'f1', name: 'Combat', order: 0),
          ],
          pads: <SoundPad>[
            SoundPad(
              id: 'p_present',
              folderId: 'f1',
              label: 'Present Sound',
              colorValue: 0xFFB84A39,
              audioPath: 'audio/present.wav',
              isAsset: false,
              type: PadType.effect,
              order: 0,
            ),
            SoundPad(
              id: 'p_missing',
              folderId: 'f1',
              label: 'Missing Sound',
              colorValue: 0xFF3E6D8C,
              audioPath: 'audio/missing.wav',
              isAsset: false,
              type: PadType.effect,
              order: 1,
            ),
          ],
        );

        final wavBytes = File(
          'test/fixtures/sample_effect.wav',
        ).readAsBytesSync();
        final partialZip = _encodeZipEntries(<String, List<int>>{
          'manifest.json': utf8.encode(jsonEncode(partialManifest.toJson())),
          'audio/present.wav': wavBytes,
        });

        await expectLater(
          () => service.importBackup(partialZip),
          throwsA(isA<BackupException>()),
        );

        // Rollback must leave zero orphaned audio files on disk.
        final remainingFiles = storeB.audioDirectory.existsSync()
            ? storeB.audioDirectory.listSync().whereType<File>().toList()
            : <File>[];
        expect(remainingFiles, isEmpty);
      },
    );
  });
}
