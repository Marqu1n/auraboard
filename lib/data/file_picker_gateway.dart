import 'dart:typed_data';

import 'package:auraboard/data/audio_file_store.dart';
import 'package:file_picker/file_picker.dart';

/// Represents a user-selected audio file returned by [FilePickerGateway].
class PickedAudioFile {
  const PickedAudioFile({required this.name, this.path, this.bytes});

  final String name;
  final String? path;
  final Uint8List? bytes;
}

/// Platform abstraction over native file pickers and save dialogs for offline
/// audio import and backup transfer.
abstract interface class FilePickerGateway {
  /// Opens a multi-file picker filtered to supported audio formats.
  Future<List<PickedAudioFile>> pickAudioFiles();

  /// Opens a file picker to select an offline `.auraboard` backup archive and
  /// returns its raw bytes, or `null` if canceled.
  Future<Uint8List?> pickBackupBytes();

  /// Opens a native save dialog to persist backup archive [bytes] under
  /// [suggestedFileName]. Returns `true` if saved, `false` if canceled.
  Future<bool> saveBackupBytes({
    required String suggestedFileName,
    required Uint8List bytes,
  });
}

/// Production [FilePickerGateway] backed by `package:file_picker`.
class PlatformFilePickerGateway implements FilePickerGateway {
  const PlatformFilePickerGateway();

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Import Audio Files',
      type: FileType.custom,
      allowedExtensions: supportedAudioExtensions.toList(),
    );

    final picked = <PickedAudioFile>[];
    for (final file in files) {
      final localPath = file.path;
      if (localPath != null && localPath.isNotEmpty) {
        picked.add(PickedAudioFile(name: file.name, path: localPath));
      } else {
        Uint8List? bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {
          bytes = null;
        }
        picked.add(PickedAudioFile(name: file.name, bytes: bytes));
      }
    }
    return picked;
  }

  @override
  Future<Uint8List?> pickBackupBytes() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import AuraBoard Backup',
      type: FileType.any,
    );
    if (file == null) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> saveBackupBytes({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Export AuraBoard Backup',
      fileName: suggestedFileName,
      bytes: bytes,
      mimeType: 'application/zip',
    );
    return savedUri != null;
  }
}
