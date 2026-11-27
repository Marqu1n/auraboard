import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auraboard/data/demo_board.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:path/path.dart' as p;

/// Atomic JSON file-backed [LibraryRepository].
///
/// Serializes all writes through an internal FIFO queue, writes UTF-8 JSON to
/// `library.json.tmp` with `flush: true`, and atomically renames over
/// `library.json`. Seeds the bundled demo library on first run and recovers
/// corrupt files by preserving a timestamped backup before re-seeding.
class FileLibraryRepository implements LibraryRepository {
  FileLibraryRepository({required this.directory});

  static const String _libraryFileName = 'library.json';
  static const String _tempFileName = 'library.json.tmp';

  final Directory directory;

  Future<void> _queue = Future<void>.value();

  File get _libraryFile => File(p.join(directory.path, _libraryFileName));

  File get _tempFile => File(p.join(directory.path, _tempFileName));

  @override
  Future<SoundLibrary> load() {
    return _enqueue<SoundLibrary>(() async {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      if (!await _libraryFile.exists()) {
        final demo = createDemoLibrary();
        await _writeAtomically(demo);
        return demo;
      }

      try {
        final raw = await _libraryFile.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Root JSON value must be an object.');
        }
        return SoundLibrary.fromJson(decoded);
      } catch (_) {
        await _backupCorruptFile();
        final demo = createDemoLibrary();
        await _writeAtomically(demo);
        return demo;
      }
    });
  }

  @override
  Future<void> save(SoundLibrary library) {
    return _enqueue<void>(() async {
      await _writeAtomically(library);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _writeAtomically(SoundLibrary library) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(library.toJson());
    final tmp = _tempFile;
    try {
      await tmp.writeAsString(encoded, encoding: utf8, flush: true);
      await tmp.rename(_libraryFile.path);
    } catch (_) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best-effort cleanup of failed temp write.
        }
      }
      rethrow;
    }
  }

  Future<void> _backupCorruptFile() async {
    if (!await _libraryFile.exists()) {
      return;
    }
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    var candidate = File(
      p.join(directory.path, '$_libraryFileName.corrupt.$timestamp'),
    );
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        p.join(directory.path, '$_libraryFileName.corrupt.$timestamp.$suffix'),
      );
      suffix++;
    }
    await _libraryFile.copy(candidate.path);
  }
}
