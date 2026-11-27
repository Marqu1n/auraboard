import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Audio file extensions supported for offline import into AuraBoard.
const Set<String> supportedAudioExtensions = <String>{
  'mp3',
  'ogg',
  'wav',
  'flac',
  'm4a',
};

/// Thrown when an audio file has an unsupported or missing extension.
class UnsupportedAudioFormatException implements Exception {
  const UnsupportedAudioFormatException(this.message);

  final String message;

  @override
  String toString() => 'UnsupportedAudioFormatException: $message';
}

/// Thrown when reading or copying an audio file into private storage fails.
class AudioImportException implements Exception {
  const AudioImportException(this.message);

  final String message;

  @override
  String toString() => 'AudioImportException: $message';
}

/// Manages app-private audio storage under `<baseDirectory>/audio`.
///
/// Copying imported user audio into app-private storage decouples playback from
/// transient Android SAF URIs or external files that the user may later move or
/// delete.
class AudioFileStore {
  AudioFileStore({required Directory baseDirectory, Uuid? uuid})
    : _baseDirectory = baseDirectory,
      _uuid = uuid ?? const Uuid();

  static const String _fallbackLabel = 'Imported Sound';

  final Directory _baseDirectory;
  final Uuid _uuid;

  /// Directory where all app-private imported audio copies are stored.
  Directory get audioDirectory =>
      Directory(p.join(_baseDirectory.path, 'audio'));

  /// Returns `true` if [filenameOrPath] ends with one of
  /// [supportedAudioExtensions] (case-insensitive).
  bool isSupportedExtension(String filenameOrPath) {
    return _extractSupportedExtension(filenameOrPath) != null;
  }

  /// Derives a clean, readable pad label from [filenameOrPath].
  ///
  /// Strips directory segments and file extension, replaces `_` and `-` with
  /// spaces, collapses repeated whitespace, and capitalizes each word. Falls
  /// back to `'Imported Sound'` when the resulting label would be blank.
  String derivePadLabel(String filenameOrPath) {
    if (filenameOrPath.trim().isEmpty) {
      return _fallbackLabel;
    }

    final normalizedSlashes = filenameOrPath.replaceAll('\\', '/');
    var base = p.posix.basenameWithoutExtension(normalizedSlashes);

    // Handle bare extension strings such as ".wav" without a stem.
    if (base.startsWith('.') &&
        supportedAudioExtensions.contains(base.substring(1).toLowerCase())) {
      return _fallbackLabel;
    }

    base = base
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (base.isEmpty) {
      return _fallbackLabel;
    }

    final words = base
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) {
          if (word.length == 1) {
            return word.toUpperCase();
          }
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');

    return words.isEmpty ? _fallbackLabel : words;
  }

  /// Validates and copies [sourcePath] into [audioDirectory], returning the
  /// absolute path to the private copy.
  Future<String> copyToPrivateStorage({
    required String sourcePath,
    String? originalFileName,
  }) async {
    final nameForExtension =
        originalFileName != null && originalFileName.trim().isNotEmpty
        ? originalFileName
        : sourcePath;
    final extension = _requireSupportedExtension(nameForExtension);

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw AudioImportException('Source audio file not found: $sourcePath');
    }

    final Uint8List bytes;
    try {
      bytes = await sourceFile.readAsBytes();
    } on FileSystemException catch (error) {
      throw AudioImportException(
        'Failed to read audio file "$sourcePath": ${error.message}',
      );
    }

    return _writeAtomically(bytes: bytes, extension: extension);
  }

  /// Validates [originalFileName] and writes [bytes] into [audioDirectory],
  /// returning the absolute path to the private copy.
  Future<String> writeBytesToPrivateStorage({
    required Uint8List bytes,
    required String originalFileName,
  }) async {
    final extension = _requireSupportedExtension(originalFileName);
    return _writeAtomically(bytes: bytes, extension: extension);
  }

  /// Deletes [audioPath] only if it resides strictly inside [audioDirectory].
  ///
  /// Paths outside [audioDirectory], traversal attempts, and missing files are
  /// safely ignored.
  Future<void> deletePrivateFile(String audioPath) async {
    if (audioPath.trim().isEmpty) {
      return;
    }

    final normalizedAudioDir = p.normalize(p.absolute(audioDirectory.path));
    final normalizedTarget = p.normalize(p.absolute(audioPath));
    if (!p.isWithin(normalizedAudioDir, normalizedTarget)) {
      return;
    }

    final targetFile = File(normalizedTarget);
    if (!await targetFile.exists()) {
      return;
    }

    try {
      final resolvedAudioDir = await audioDirectory.resolveSymbolicLinks();
      final resolvedTarget = await targetFile.resolveSymbolicLinks();
      if (!p.isWithin(resolvedAudioDir, resolvedTarget)) {
        return;
      }
      await targetFile.delete();
    } on FileSystemException {
      // Best-effort cleanup; ignore races if already removed.
    }
  }

  String? _extractSupportedExtension(String filenameOrPath) {
    final trimmed = filenameOrPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final rawExt = p.extension(trimmed.replaceAll('\\', '/'));
    if (rawExt.length <= 1) {
      return null;
    }
    final normalizedExt = rawExt.substring(1).toLowerCase();
    return supportedAudioExtensions.contains(normalizedExt)
        ? normalizedExt
        : null;
  }

  String _requireSupportedExtension(String filenameOrPath) {
    final ext = _extractSupportedExtension(filenameOrPath);
    if (ext == null) {
      throw UnsupportedAudioFormatException(
        'Unsupported audio format for "$filenameOrPath". '
        'Supported formats: ${supportedAudioExtensions.join(', ')}.',
      );
    }
    return ext;
  }

  Future<String> _writeAtomically({
    required Uint8List bytes,
    required String extension,
  }) async {
    final dir = audioDirectory;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = '${_uuid.v4()}.$extension';
    final targetPath = p.join(dir.path, fileName);
    final tempFile = File('$targetPath.tmp');

    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetPath);
      return targetPath;
    } on FileSystemException catch (error) {
      await _cleanupTempFile(tempFile);
      throw AudioImportException(
        'Failed to store audio file "$fileName": ${error.message}',
      );
    } catch (_) {
      await _cleanupTempFile(tempFile);
      rethrow;
    }
  }

  Future<void> _cleanupTempFile(File tempFile) async {
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } on FileSystemException {
        // Best-effort temp cleanup.
      }
    }
  }
}
