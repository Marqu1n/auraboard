import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:auraboard/data/audio_file_store.dart';
import 'package:auraboard/domain/models.dart';
import 'package:path/path.dart' as p;

/// Thrown when exporting or importing an offline `.auraboard` backup fails.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// Offline single-file ZIP backup exporter and importer for [SoundLibrary].
///
/// Archives contain a portable `manifest.json` alongside every non-asset audio
/// file stored under `audio/<unique_basename>`.
class BackupService {
  BackupService({required AudioFileStore audioFileStore})
    : _audioFileStore = audioFileStore;

  static const int backupVersion = 1;
  static const String manifestFileName = 'manifest.json';

  final AudioFileStore _audioFileStore;

  /// Exports [library] and all existing non-asset audio files into a portable
  /// ZIP archive byte buffer.
  Future<Uint8List> exportBackup(SoundLibrary library) async {
    final archive = Archive();
    final portablePathBySource = <String, String>{};
    final usedArchivePaths = <String>{};
    final portablePads = <SoundPad>[];

    for (final pad in library.pads) {
      if (pad.isAsset) {
        portablePads.add(pad);
        continue;
      }

      final sourceFile = File(pad.audioPath);
      if (!await sourceFile.exists()) {
        portablePads.add(pad);
        continue;
      }

      final sourceKey = p.normalize(p.absolute(pad.audioPath));
      var archivePath = portablePathBySource[sourceKey];
      if (archivePath == null) {
        final uniqueBaseName = _allocateUniqueAudioBaseName(
          pad: pad,
          usedArchivePaths: usedArchivePaths,
        );
        archivePath = 'audio/$uniqueBaseName';
        final bytes = await sourceFile.readAsBytes();
        archive.addFile(ArchiveFile.bytes(archivePath, bytes));
        portablePathBySource[sourceKey] = archivePath;
        usedArchivePaths.add(archivePath);
      }

      portablePads.add(pad.copyWith(audioPath: archivePath));
    }

    final portableLibrary = library.copyWith(
      pads: List<SoundPad>.unmodifiable(portablePads),
    );
    final manifestMap = <String, dynamic>{
      'backupVersion': backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      ...portableLibrary.toJson(),
    };
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifestMap),
    );
    archive.addFile(ArchiveFile.bytes(manifestFileName, manifestBytes));

    return ZipEncoder().encodeBytes(archive);
  }

  /// Validates and imports a backup ZIP archive, extracting audio files into
  /// [AudioFileStore.audioDirectory] and rewriting non-asset pad paths to the
  /// target device's local private paths.
  Future<SoundLibrary> importBackup(Uint8List archiveBytes) async {
    if (archiveBytes.isEmpty) {
      throw const BackupException('Backup archive is empty.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        archiveBytes,
        verify: true,
        throwOnError: true,
      );
    } catch (error) {
      throw BackupException('Invalid or corrupted backup archive: $error');
    }

    // Security gate: validate EVERY archive entry before touching disk.
    for (final entry in archive.files) {
      _validateArchiveEntryPath(entry.name);
      if (entry.isSymbolicLink) {
        throw BackupException(
          'Backup archive contains disallowed symbolic link: ${entry.name}',
        );
      }
    }

    final manifestEntry = archive.findFile(manifestFileName);
    if (manifestEntry == null || !manifestEntry.isFile) {
      throw const BackupException('Backup archive is missing manifest.json.');
    }

    final SoundLibrary parsedLibrary = _parseManifest(manifestEntry);

    // Validate every referenced relative audio path before extracting anything.
    final referencedAudioEntries = <String>{};
    for (final pad in parsedLibrary.pads) {
      if (!pad.isAsset && pad.audioPath.startsWith('audio/')) {
        _validateArchiveEntryPath(pad.audioPath);
        referencedAudioEntries.add(pad.audioPath);
      }
    }

    final extractedPathByEntryName = <String, String>{};
    final createdFiles = <String>[];

    try {
      for (final entry in archive.files) {
        if (!entry.isFile || entry.name == manifestFileName) {
          continue;
        }
        if (!referencedAudioEntries.contains(entry.name)) {
          continue;
        }
        final entryBytes = entry.readBytes();
        if (entryBytes == null) {
          throw BackupException(
            'Unable to read audio entry "${entry.name}" from backup archive.',
          );
        }
        final baseName = p.posix.basename(entry.name);
        final storedPath = await _audioFileStore.writeBytesToPrivateStorage(
          bytes: entryBytes,
          originalFileName: baseName,
        );
        extractedPathByEntryName[entry.name] = storedPath;
        createdFiles.add(storedPath);
      }

      final restoredPads = <SoundPad>[];
      for (final pad in parsedLibrary.pads) {
        if (pad.isAsset) {
          restoredPads.add(pad);
          continue;
        }
        final extractedPath = extractedPathByEntryName[pad.audioPath];
        if (extractedPath != null) {
          restoredPads.add(pad.copyWith(audioPath: extractedPath));
        } else if (pad.audioPath.startsWith('audio/')) {
          throw BackupException(
            'Backup archive is missing audio file "${pad.audioPath}".',
          );
        } else {
          restoredPads.add(pad);
        }
      }

      return parsedLibrary.copyWith(
        pads: List<SoundPad>.unmodifiable(restoredPads),
      );
    } on BackupException {
      await _rollbackExtractedFiles(createdFiles);
      rethrow;
    } catch (error) {
      await _rollbackExtractedFiles(createdFiles);
      throw BackupException('Failed to import backup: $error');
    }
  }

  SoundLibrary _parseManifest(ArchiveFile manifestEntry) {
    try {
      final rawBytes = manifestEntry.readBytes();
      if (rawBytes == null) {
        throw const BackupException('Unable to read manifest.json.');
      }
      final decoded = jsonDecode(utf8.decode(rawBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const BackupException('Backup manifest must be a JSON object.');
      }

      final Map<String, dynamic> libraryJson;
      if (decoded['library'] is Map<String, dynamic> &&
          !decoded.containsKey('folders')) {
        libraryJson = decoded['library'] as Map<String, dynamic>;
      } else {
        libraryJson = decoded;
      }

      if (libraryJson['folders'] is! List<dynamic> ||
          libraryJson['pads'] is! List<dynamic>) {
        throw const BackupException(
          'Backup manifest is missing valid folders or pads lists.',
        );
      }

      final library = SoundLibrary.fromJson(libraryJson);
      if (library.folders.isEmpty) {
        throw const BackupException(
          'Backup manifest must contain at least one folder.',
        );
      }
      return library;
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupException('Malformed backup manifest: $error');
    }
  }

  void _validateArchiveEntryPath(String entryName) {
    if (entryName.isEmpty) {
      throw const BackupException('Backup archive contains an empty path.');
    }
    if (entryName.contains('\x00')) {
      throw BackupException(
        'Backup archive path contains invalid null byte: $entryName',
      );
    }
    if (entryName.contains('\\')) {
      throw BackupException(
        'Backup archive path contains disallowed backslash: $entryName',
      );
    }
    if (entryName.startsWith('/')) {
      throw BackupException(
        'Backup archive contains absolute path: $entryName',
      );
    }
    if (RegExp(r'^[a-zA-Z]:').hasMatch(entryName)) {
      throw BackupException(
        'Backup archive contains drive-prefixed path: $entryName',
      );
    }

    final segments = entryName.split('/');
    for (final segment in segments) {
      if (segment == '..') {
        throw BackupException(
          'Backup archive contains path traversal segment: $entryName',
        );
      }
    }

    final normalized = p.posix.normalize(entryName);
    if (normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.startsWith('/')) {
      throw BackupException(
        'Backup archive path escapes root directory: $entryName',
      );
    }
  }

  String _allocateUniqueAudioBaseName({
    required SoundPad pad,
    required Set<String> usedArchivePaths,
  }) {
    final normalizedPath = pad.audioPath.replaceAll('\\', '/');
    var baseName = p.posix.basename(normalizedPath);
    if (baseName.isEmpty ||
        baseName == '.' ||
        baseName == '..' ||
        baseName.contains('/')) {
      final ext = p.posix.extension(normalizedPath);
      baseName = '${pad.id}$ext';
    }

    if (!usedArchivePaths.contains('audio/$baseName')) {
      return baseName;
    }

    final stem = p.posix.basenameWithoutExtension(baseName);
    final ext = p.posix.extension(baseName);
    var suffix = 1;
    while (usedArchivePaths.contains('audio/${stem}_$suffix$ext')) {
      suffix++;
    }
    return '${stem}_$suffix$ext';
  }

  Future<void> _rollbackExtractedFiles(List<String> createdFiles) async {
    for (final filePath in createdFiles) {
      await _audioFileStore.deletePrivateFile(filePath);
    }
  }
}
