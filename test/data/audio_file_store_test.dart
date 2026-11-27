import 'dart:io';
import 'dart:typed_data';

import 'package:auraboard/data/audio_file_store.dart';
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

void main() {
  group('AudioFileStore', () {
    test('exposes the 5 supported audio extensions', () {
      expect(
        supportedAudioExtensions,
        equals(const <String>{'mp3', 'ogg', 'wav', 'flac', 'm4a'}),
      );
    });

    test('audioDirectory points to <baseDirectory>/audio', () {
      final baseDir = _createTempDir('auraboard_audio_store_dir_');
      final store = AudioFileStore(baseDirectory: baseDir);

      expect(store.audioDirectory.path, equals(p.join(baseDir.path, 'audio')));
    });

    test('isSupportedExtension validates all 5 formats case-insensitively', () {
      final baseDir = _createTempDir('auraboard_audio_store_ext_');
      final store = AudioFileStore(baseDirectory: baseDir);

      for (final valid in const <String>[
        'sword.mp3',
        'tavern.ogg',
        'thunder.wav',
        'forest.flac',
        'boss_theme.m4a',
        '/storage/emulated/0/Music/DRAGON_ROAR.MP3',
        '/tmp/HIT.WAV',
        'ambience.OGG',
        'cave.FlAc',
        'lute.M4A',
      ]) {
        expect(
          store.isSupportedExtension(valid),
          isTrue,
          reason: 'Expected "$valid" to be supported',
        );
      }

      for (final invalid in const <String>[
        'notes.txt',
        'cover.png',
        'library.json',
        'script.sh',
        'no_extension',
        'trailing_dot.',
        '',
      ]) {
        expect(
          store.isSupportedExtension(invalid),
          isFalse,
          reason: 'Expected "$invalid" to be rejected',
        );
      }
    });

    test('derivePadLabel formats filenames cleanly with blank fallback', () {
      final baseDir = _createTempDir('auraboard_audio_store_label_');
      final store = AudioFileStore(baseDirectory: baseDir);

      expect(store.derivePadLabel('dragon_roar-01.mp3'), 'Dragon Roar 01');
      expect(
        store.derivePadLabel('/storage/emulated/0/Music/tavern_lute-loop.ogg'),
        'Tavern Lute Loop',
      );
      expect(store.derivePadLabel('  .wav'), 'Imported Sound');
      expect(store.derivePadLabel('___---.mp3'), 'Imported Sound');
      expect(store.derivePadLabel(''), 'Imported Sound');
    });

    test(
      'copyToPrivateStorage copies fixture bytes independently of original source file',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_copy_');
        final externalDir = _createTempDir('auraboard_audio_external_');
        final store = AudioFileStore(baseDirectory: baseDir);

        final fixtureBytes = File(
          'test/fixtures/sample_effect.wav',
        ).readAsBytesSync();
        final externalSource = File(p.join(externalDir.path, 'goblin_hit.wav'))
          ..writeAsBytesSync(fixtureBytes);

        final storedPath = await store.copyToPrivateStorage(
          sourcePath: externalSource.path,
        );

        expect(p.isWithin(store.audioDirectory.path, storedPath), isTrue);
        expect(p.extension(storedPath).toLowerCase(), '.wav');

        // Delete the external source file to simulate Android external storage
        // removal or revoked SAF URI permission.
        externalSource.deleteSync();
        expect(externalSource.existsSync(), isFalse);

        final privateCopy = File(storedPath);
        expect(privateCopy.existsSync(), isTrue);
        expect(privateCopy.readAsBytesSync(), equals(fixtureBytes));
      },
    );

    test(
      'copyToPrivateStorage supports all 5 extensions including uppercase variants',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_formats_');
        final externalDir = _createTempDir('auraboard_audio_formats_src_');
        final store = AudioFileStore(baseDirectory: baseDir);

        const filenames = <String>[
          'track.mp3',
          'track.ogg',
          'track.wav',
          'track.flac',
          'track.m4a',
          'LOUD_HORN.MP3',
          'DRUM_HIT.WAV',
        ];

        for (var i = 0; i < filenames.length; i++) {
          final name = filenames[i];
          final payload = Uint8List.fromList(<int>[1, 2, 3, 4, i]);
          final src = File(p.join(externalDir.path, name))
            ..writeAsBytesSync(payload);

          final storedPath = await store.copyToPrivateStorage(
            sourcePath: src.path,
          );

          expect(p.isWithin(store.audioDirectory.path, storedPath), isTrue);
          expect(
            p.extension(storedPath).toLowerCase(),
            p.extension(name).toLowerCase(),
          );
          expect(File(storedPath).readAsBytesSync(), equals(payload));
        }
      },
    );

    test(
      'copyToPrivateStorage rejects unsupported extensions with UnsupportedAudioFormatException',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_reject_');
        final store = AudioFileStore(baseDirectory: baseDir);

        await expectLater(
          () => store.copyToPrivateStorage(
            sourcePath: 'test/fixtures/unsupported.txt',
          ),
          throwsA(isA<UnsupportedAudioFormatException>()),
        );
      },
    );

    test(
      'copyToPrivateStorage rejects missing source file with AudioImportException',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_missing_');
        final store = AudioFileStore(baseDirectory: baseDir);

        final missingPath = p.join(baseDir.path, 'does_not_exist.wav');
        await expectLater(
          () => store.copyToPrivateStorage(sourcePath: missingPath),
          throwsA(isA<AudioImportException>()),
        );
      },
    );

    test(
      'writeBytesToPrivateStorage writes bytes cleanly into audioDirectory with matching extension',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_bytes_');
        final store = AudioFileStore(baseDirectory: baseDir);
        final bytes = File('test/fixtures/sample_effect.wav').readAsBytesSync();

        final storedPath = await store.writeBytesToPrivateStorage(
          bytes: bytes,
          originalFileName: 'saf_thunder.WAV',
        );

        expect(p.isWithin(store.audioDirectory.path, storedPath), isTrue);
        expect(p.extension(storedPath).toLowerCase(), '.wav');
        expect(File(storedPath).readAsBytesSync(), equals(bytes));

        await expectLater(
          () => store.writeBytesToPrivateStorage(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            originalFileName: 'notes.txt',
          ),
          throwsA(isA<UnsupportedAudioFormatException>()),
        );
      },
    );

    test(
      'deletePrivateFile deletes files inside audioDirectory and refuses files outside',
      () async {
        final baseDir = _createTempDir('auraboard_audio_store_delete_');
        final store = AudioFileStore(baseDirectory: baseDir);
        final bytes = Uint8List.fromList(<int>[10, 20, 30, 40]);

        final privatePath = await store.writeBytesToPrivateStorage(
          bytes: bytes,
          originalFileName: 'removable.ogg',
        );
        expect(File(privatePath).existsSync(), isTrue);

        await store.deletePrivateFile(privatePath);
        expect(File(privatePath).existsSync(), isFalse);

        // Missing file inside audioDirectory should be a safe no-op.
        await store.deletePrivateFile(privatePath);

        // File outside audioDirectory must never be deleted.
        final outsideFile = File(p.join(baseDir.path, 'library.json'))
          ..writeAsStringSync('{"keep": true}');
        await store.deletePrivateFile(outsideFile.path);
        expect(outsideFile.existsSync(), isTrue);

        // Path traversal attempt pointing outside audioDirectory must also be ignored.
        final traversalPath = p.join(
          store.audioDirectory.path,
          '..',
          'library.json',
        );
        await store.deletePrivateFile(traversalPath);
        expect(outsideFile.existsSync(), isTrue);
      },
    );
  });
}
