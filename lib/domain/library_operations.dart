import 'package:auraboard/domain/models.dart';

/// Pure, immutable domain operations for mutating a [SoundLibrary].
abstract final class LibraryOperations {
  /// Creates a new folder with a trimmed [name] appended after existing folders.
  ///
  /// Throws [ArgumentError] if [name] is empty or whitespace-only.
  static SoundLibrary createFolder(
    SoundLibrary library, {
    required String id,
    required String name,
  }) {
    final trimmedName = _requireNonBlankName(name, 'name');
    final sortedFolders = _sortedFolders(library.folders);
    final normalizedExisting = _normalizeFolderOrders(sortedFolders);
    final created = SoundFolder(
      id: id,
      name: trimmedName,
      order: normalizedExisting.length,
    );
    return library.copyWith(
      folders: List<SoundFolder>.unmodifiable(<SoundFolder>[
        ...normalizedExisting,
        created,
      ]),
    );
  }

  /// Renames the folder matching [folderId] to trimmed [newName].
  ///
  /// Throws [ArgumentError] if [newName] is empty or whitespace-only.
  static SoundLibrary renameFolder(
    SoundLibrary library, {
    required String folderId,
    required String newName,
  }) {
    final trimmedName = _requireNonBlankName(newName, 'newName');
    final updatedFolders = library.folders
        .map(
          (folder) => folder.id == folderId
              ? folder.copyWith(name: trimmedName)
              : folder,
        )
        .toList();
    return library.copyWith(
      folders: List<SoundFolder>.unmodifiable(updatedFolders),
    );
  }

  /// Reorders folders sorted by existing [SoundFolder.order], moving the item
  /// at [oldIndex] to target index [newIndex], and normalizes orders `0..n-1`.
  static SoundLibrary reorderFolders(
    SoundLibrary library,
    int oldIndex,
    int newIndex,
  ) {
    final sortedFolders = _sortedFolders(library.folders);
    RangeError.checkValidIndex(oldIndex, sortedFolders, 'oldIndex');
    RangeError.checkValidIndex(newIndex, sortedFolders, 'newIndex');

    final moved = sortedFolders.removeAt(oldIndex);
    sortedFolders.insert(newIndex, moved);

    return library.copyWith(
      folders: List<SoundFolder>.unmodifiable(
        _normalizeFolderOrders(sortedFolders),
      ),
    );
  }

  /// Deletes [folderId] and normalizes remaining folder orders `0..n-1`.
  ///
  /// When [movePadsToFolderId] is provided, pads from the deleted folder are
  /// appended to that folder in order; otherwise they are removed.
  ///
  /// Throws [StateError] if deleting the last remaining folder.
  static SoundLibrary deleteFolder(
    SoundLibrary library, {
    required String folderId,
    String? movePadsToFolderId,
  }) {
    if (library.folders.length <= 1) {
      throw StateError('Cannot delete the last remaining folder.');
    }

    final remainingFolders = _normalizeFolderOrders(
      _sortedFolders(
        library.folders.where((folder) => folder.id != folderId).toList(),
      ),
    );

    if (movePadsToFolderId == null) {
      final remainingPads = library.pads
          .where((pad) => pad.folderId != folderId)
          .toList();
      return library.copyWith(
        folders: List<SoundFolder>.unmodifiable(remainingFolders),
        pads: List<SoundPad>.unmodifiable(remainingPads),
      );
    }

    if (movePadsToFolderId == folderId ||
        !remainingFolders.any((folder) => folder.id == movePadsToFolderId)) {
      throw ArgumentError.value(
        movePadsToFolderId,
        'movePadsToFolderId',
        'Target folder must be a different existing folder.',
      );
    }

    final orphanedPads = _sortedPads(
      library.pads.where((pad) => pad.folderId == folderId).toList(),
    ).map((pad) => pad.copyWith(folderId: movePadsToFolderId)).toList();

    final existingTargetPads = _sortedPads(
      library.pads.where((pad) => pad.folderId == movePadsToFolderId).toList(),
    );

    final mergedTargetPads = _normalizePadOrders(<SoundPad>[
      ...existingTargetPads,
      ...orphanedPads,
    ]);

    final untouchedPads = library.pads
        .where(
          (pad) =>
              pad.folderId != folderId && pad.folderId != movePadsToFolderId,
        )
        .toList();

    return library.copyWith(
      folders: List<SoundFolder>.unmodifiable(remainingFolders),
      pads: List<SoundPad>.unmodifiable(<SoundPad>[
        ...untouchedPads,
        ...mergedTargetPads,
      ]),
    );
  }

  /// Reorders pads within [folderId] from [oldIndex] to target index [newIndex]
  /// and normalizes orders `0..n-1`, leaving other folders untouched.
  static SoundLibrary reorderPadsInFolder(
    SoundLibrary library, {
    required String folderId,
    required int oldIndex,
    required int newIndex,
  }) {
    final folderPads = _sortedPads(
      library.pads.where((pad) => pad.folderId == folderId).toList(),
    );
    RangeError.checkValidIndex(oldIndex, folderPads, 'oldIndex');
    RangeError.checkValidIndex(newIndex, folderPads, 'newIndex');

    final moved = folderPads.removeAt(oldIndex);
    folderPads.insert(newIndex, moved);
    final normalizedFolderPads = _normalizePadOrders(folderPads);

    final otherPads = library.pads
        .where((pad) => pad.folderId != folderId)
        .toList();

    return library.copyWith(
      pads: List<SoundPad>.unmodifiable(<SoundPad>[
        ...otherPads,
        ...normalizedFolderPads,
      ]),
    );
  }

  /// Moves [padId] to the end of [targetFolderId] and normalizes pad orders in
  /// both source and target folders. No-op if the pad is already there.
  static SoundLibrary movePadToFolder(
    SoundLibrary library, {
    required String padId,
    required String targetFolderId,
  }) {
    final padIndex = library.pads.indexWhere((pad) => pad.id == padId);
    if (padIndex < 0) {
      throw ArgumentError.value(padId, 'padId', 'Pad not found in library.');
    }
    if (!library.folders.any((folder) => folder.id == targetFolderId)) {
      throw ArgumentError.value(
        targetFolderId,
        'targetFolderId',
        'Target folder not found in library.',
      );
    }

    final pad = library.pads[padIndex];
    final sourceFolderId = pad.folderId;
    if (sourceFolderId == targetFolderId) {
      return library;
    }

    final sourcePads = _normalizePadOrders(
      _sortedPads(
        library.pads
            .where((p) => p.folderId == sourceFolderId && p.id != padId)
            .toList(),
      ),
    );

    final targetPads = _normalizePadOrders(<SoundPad>[
      ..._sortedPads(
        library.pads.where((p) => p.folderId == targetFolderId).toList(),
      ),
      pad.copyWith(folderId: targetFolderId),
    ]);

    final otherPads = library.pads
        .where(
          (p) => p.folderId != sourceFolderId && p.folderId != targetFolderId,
        )
        .toList();

    return library.copyWith(
      pads: List<SoundPad>.unmodifiable(<SoundPad>[
        ...otherPads,
        ...sourcePads,
        ...targetPads,
      ]),
    );
  }

  /// Replaces the pad matching [updatedPad.id]. If [updatedPad.folderId]
  /// changed, moves the pad to the end of the target folder and normalizes
  /// both source and target folder orders.
  static SoundLibrary updatePad(SoundLibrary library, SoundPad updatedPad) {
    final existingIndex = library.pads.indexWhere(
      (pad) => pad.id == updatedPad.id,
    );
    if (existingIndex < 0) {
      throw ArgumentError.value(
        updatedPad.id,
        'updatedPad',
        'Pad not found in library.',
      );
    }

    final existing = library.pads[existingIndex];
    if (existing.folderId == updatedPad.folderId) {
      final replaced = List<SoundPad>.from(library.pads);
      replaced[existingIndex] = updatedPad;
      return library.copyWith(pads: List<SoundPad>.unmodifiable(replaced));
    }

    final updatedInPlace = List<SoundPad>.from(library.pads);
    updatedInPlace[existingIndex] = updatedPad.copyWith(
      folderId: existing.folderId,
    );
    return movePadToFolder(
      library.copyWith(pads: List<SoundPad>.unmodifiable(updatedInPlace)),
      padId: updatedPad.id,
      targetFolderId: updatedPad.folderId,
    );
  }

  /// Removes [padId] and normalizes remaining pad orders in its folder.
  static SoundLibrary deletePad(SoundLibrary library, String padId) {
    final existingIndex = library.pads.indexWhere((pad) => pad.id == padId);
    if (existingIndex < 0) {
      return library;
    }

    final folderId = library.pads[existingIndex].folderId;
    final remainingInFolder = _normalizePadOrders(
      _sortedPads(
        library.pads
            .where((pad) => pad.folderId == folderId && pad.id != padId)
            .toList(),
      ),
    );
    final otherPads = library.pads
        .where((pad) => pad.folderId != folderId)
        .toList();

    return library.copyWith(
      pads: List<SoundPad>.unmodifiable(<SoundPad>[
        ...otherPads,
        ...remainingInFolder,
      ]),
    );
  }

  /// Appends [newPads] to their respective target folders with sequential
  /// orders `0..n-1`. Empty input is a clean no-op.
  static SoundLibrary addPads(SoundLibrary library, List<SoundPad> newPads) {
    if (newPads.isEmpty) {
      return library;
    }

    final additionsByFolder = <String, List<SoundPad>>{};
    for (final pad in newPads) {
      additionsByFolder.putIfAbsent(pad.folderId, () => <SoundPad>[]).add(pad);
    }

    final affectedFolderIds = additionsByFolder.keys.toSet();
    final untouchedPads = library.pads
        .where((pad) => !affectedFolderIds.contains(pad.folderId))
        .toList();

    final updatedFolderPads = <SoundPad>[];
    for (final entry in additionsByFolder.entries) {
      final folderId = entry.key;
      final existing = _sortedPads(
        library.pads.where((pad) => pad.folderId == folderId).toList(),
      );
      updatedFolderPads.addAll(
        _normalizePadOrders(<SoundPad>[...existing, ...entry.value]),
      );
    }

    return library.copyWith(
      pads: List<SoundPad>.unmodifiable(<SoundPad>[
        ...untouchedPads,
        ...updatedFolderPads,
      ]),
    );
  }

  static String _requireNonBlankName(String value, String paramName) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        value,
        paramName,
        'Folder name must not be empty or whitespace-only.',
      );
    }
    return trimmed;
  }

  static List<SoundFolder> _sortedFolders(List<SoundFolder> folders) {
    return List<SoundFolder>.from(folders)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  static List<SoundFolder> _normalizeFolderOrders(List<SoundFolder> folders) {
    return <SoundFolder>[
      for (var i = 0; i < folders.length; i++) folders[i].copyWith(order: i),
    ];
  }

  static List<SoundPad> _sortedPads(List<SoundPad> pads) {
    return List<SoundPad>.from(pads)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  static List<SoundPad> _normalizePadOrders(List<SoundPad> pads) {
    return <SoundPad>[
      for (var i = 0; i < pads.length; i++) pads[i].copyWith(order: i),
    ];
  }
}
