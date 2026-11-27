import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:auraboard/ui/widgets/folder_manager_sheet.dart';
import 'package:auraboard/ui/widgets/now_playing_bar.dart';
import 'package:auraboard/ui/widgets/pad_editor_sheet.dart';
import 'package:auraboard/ui/widgets/pad_tile.dart';
import 'package:auraboard/ui/widgets/settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Primary soundboard screen supporting safe Play Mode (default) and explicit
/// Edit Mode for folder/pad customization, drag-and-drop reordering, and
/// moving pads across folders.
class SoundboardScreen extends ConsumerStatefulWidget {
  const SoundboardScreen({super.key});

  @override
  ConsumerState<SoundboardScreen> createState() => _SoundboardScreenState();
}

class _SoundboardScreenState extends ConsumerState<SoundboardScreen> {
  String? _selectedFolderId;

  Future<void> _handleAddFolder() async {
    final name = await showFolderNameDialog(
      context,
      title: 'New Folder',
      confirmLabel: 'Create',
    );
    if (name != null && mounted) {
      await ref.read(libraryControllerProvider.notifier).createFolder(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final libraryAsync = ref.watch(libraryControllerProvider);
    final playbackState = ref.watch(playbackControllerProvider);
    final isEditMode = ref.watch(editModeProvider);
    final mediaQuery = MediaQuery.of(context);
    final isShortViewport = mediaQuery.size.height < 420;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AuraBoard'),
        toolbarHeight: isShortViewport ? 48 : null,
        actions: <Widget>[
          IconButton(
            key: const Key('edit_mode_toggle'),
            tooltip: isEditMode ? 'Exit edit mode' : 'Edit mode',
            isSelected: isEditMode,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            style: isEditMode
                ? IconButton.styleFrom(
                    backgroundColor: colorScheme.tertiaryContainer,
                    foregroundColor: colorScheme.onTertiaryContainer,
                  )
                : null,
            icon: Icon(isEditMode ? Icons.check_rounded : Icons.edit_outlined),
            onPressed: () => ref.read(editModeProvider.notifier).toggle(),
          ),
          IconButton(
            key: const Key('settings_button'),
            tooltip: 'Settings',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.settings),
            onPressed: () => showSettingsSheet(context),
          ),
        ],
      ),
      body: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Failed to load soundboard: $error')),
        data: (library) {
          final folders = List<SoundFolder>.from(library.folders)
            ..sort((a, b) => a.order.compareTo(b.order));

          final padsById = <String, SoundPad>{
            for (final pad in library.pads) pad.id: pad,
          };

          final activeEntries =
              playbackState.activeByPad.values
                  .where(
                    (voice) =>
                        voice.phase == PadPlaybackPhase.fadingIn ||
                        voice.phase == PadPlaybackPhase.playing ||
                        voice.phase == PadPlaybackPhase.fadingOut,
                  )
                  .map((voice) {
                    final pad = padsById[voice.padId];
                    if (pad == null) {
                      return null;
                    }
                    return ActiveSoundEntry(pad: pad, voice: voice);
                  })
                  .whereType<ActiveSoundEntry>()
                  .toList()
                ..sort((a, b) {
                  final aStart = a.voice.startedAt;
                  final bStart = b.voice.startedAt;
                  if (aStart != null && bStart != null) {
                    final cmp = aStart.compareTo(bStart);
                    if (cmp != 0) {
                      return cmp;
                    }
                  }
                  return a.pad.label.compareTo(b.pad.label);
                });

          final playbackNotifier = ref.read(
            playbackControllerProvider.notifier,
          );
          final libraryNotifier = ref.read(libraryControllerProvider.notifier);

          final editModeBanner = isEditMode
              ? _EditModeBanner(
                  onAddFolder: _handleAddFolder,
                  onManageFolders: () => showFolderManagerSheet(context),
                )
              : null;

          if (folders.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ?editModeBanner,
                const Expanded(
                  child: Center(child: Text('No folders available')),
                ),
                NowPlayingBar(
                  activeEntries: activeEntries,
                  masterVolume: library.settings.masterVolume,
                  onMasterVolumeChanged: playbackNotifier.setMasterVolume,
                  onPadVolumeChanged: playbackNotifier.setPadVolume,
                  onStopPad: playbackNotifier.stopPad,
                  onStopAll: playbackNotifier.stopAll,
                ),
              ],
            );
          }

          final effectiveFolderId =
              folders.any((folder) => folder.id == _selectedFolderId)
              ? _selectedFolderId!
              : folders.first.id;

          final visiblePads =
              library.pads
                  .where((pad) => pad.folderId == effectiveFolderId)
                  .toList()
                ..sort((a, b) => a.order.compareTo(b.order));

          final density = library.settings.gridDensity;
          final textScale = mediaQuery.textScaler.scale(14.0) / 14.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ?editModeBanner,
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isShortViewport ? 2 : 6,
                ),
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < folders.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 8),
                      _FolderChip(
                        folder: folders[i],
                        selected: folders[i].id == effectiveFolderId,
                        isShortViewport: isShortViewport,
                        isEditMode: isEditMode,
                        padsById: padsById,
                        onSelected: () {
                          setState(() {
                            _selectedFolderId = folders[i].id;
                          });
                        },
                        onPadDropped: (padId) {
                          libraryNotifier.movePadToFolder(padId, folders[i].id);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: visiblePads.isEmpty
                    ? const Center(child: Text('No pads in this folder'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final horizontalPadding = constraints.maxWidth >= 600
                              ? 16.0
                              : 12.0;
                          final availableWidth =
                              constraints.maxWidth - (horizontalPadding * 2);
                          final crossAxisCount = _columnCountForWidth(
                            availableWidth,
                            density,
                          );
                          final mainAxisExtent = _tileHeightForDensity(
                            density,
                            textScale,
                          );
                          final spacing = density == GridDensity.compact
                              ? 8.0
                              : 12.0;
                          final tileWidth =
                              ((availableWidth -
                                          (spacing * (crossAxisCount - 1))) /
                                      crossAxisCount)
                                  .clamp(48.0, double.infinity);

                          return GridView.builder(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              isShortViewport ? 4 : 8,
                              horizontalPadding,
                              isShortViewport ? 8 : 16,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisExtent: mainAxisExtent,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                ),
                            itemCount: visiblePads.length,
                            itemBuilder: (context, index) {
                              final pad = visiblePads[index];
                              final voice = playbackState.activeByPad[pad.id];

                              if (!isEditMode) {
                                return PadTile(
                                  pad: pad,
                                  voice: voice,
                                  density: density,
                                  onTap: () => playbackNotifier.tapPad(pad),
                                );
                              }

                              return DragTarget<String>(
                                onWillAcceptWithDetails: (details) =>
                                    details.data != pad.id,
                                onAcceptWithDetails: (details) {
                                  final draggedPadId = details.data;
                                  final oldIndex = visiblePads.indexWhere(
                                    (candidate) => candidate.id == draggedPadId,
                                  );
                                  if (oldIndex != -1 && oldIndex != index) {
                                    libraryNotifier.reorderPadsInFolder(
                                      effectiveFolderId,
                                      oldIndex,
                                      index,
                                    );
                                  }
                                },
                                builder: (context, candidateData, _) {
                                  final tile = PadTile(
                                    pad: pad,
                                    voice: voice,
                                    density: density,
                                    isEditMode: true,
                                    isDropTarget: candidateData.isNotEmpty,
                                    onTap: () =>
                                        showPadEditorSheet(context, pad: pad),
                                  );
                                  return Draggable<String>(
                                    data: pad.id,
                                    feedback: Material(
                                      color: Colors.transparent,
                                      elevation: 8,
                                      borderRadius: BorderRadius.circular(16),
                                      child: SizedBox(
                                        width: tileWidth,
                                        height: mainAxisExtent,
                                        child: Opacity(
                                          opacity: 0.9,
                                          child: PadTile(
                                            pad: pad,
                                            voice: voice,
                                            density: density,
                                            isEditMode: true,
                                            onTap: () {},
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.35,
                                      child: tile,
                                    ),
                                    child: tile,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
              NowPlayingBar(
                activeEntries: activeEntries,
                masterVolume: library.settings.masterVolume,
                onMasterVolumeChanged: playbackNotifier.setMasterVolume,
                onPadVolumeChanged: playbackNotifier.setPadVolume,
                onStopPad: playbackNotifier.stopPad,
                onStopAll: playbackNotifier.stopAll,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner({
    required this.onAddFolder,
    required this.onManageFolders,
  });

  final VoidCallback onAddFolder;
  final VoidCallback onManageFolders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.tertiaryContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.edit_note,
                  size: 20,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit Mode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              IconButton(
                key: const Key('add_folder_button'),
                tooltip: 'Add folder',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  Icons.create_new_folder_outlined,
                  color: colorScheme.onTertiaryContainer,
                ),
                onPressed: onAddFolder,
              ),
              IconButton(
                key: const Key('manage_folders_button'),
                tooltip: 'Manage folders',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  Icons.folder_copy_outlined,
                  color: colorScheme.onTertiaryContainer,
                ),
                onPressed: onManageFolders,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.folder,
    required this.selected,
    required this.isShortViewport,
    required this.isEditMode,
    required this.padsById,
    required this.onSelected,
    required this.onPadDropped,
  });

  final SoundFolder folder;
  final bool selected;
  final bool isShortViewport;
  final bool isEditMode;
  final Map<String, SoundPad> padsById;
  final VoidCallback onSelected;
  final ValueChanged<String> onPadDropped;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildChip({required bool highlighted}) {
      return ChoiceChip(
        label: Text(folder.name),
        selected: selected,
        side: highlighted
            ? BorderSide(color: colorScheme.primary, width: 2)
            : null,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: isShortViewport ? 8 : 13,
        ),
        onSelected: (_) => onSelected(),
      );
    }

    if (!isEditMode) {
      return buildChip(highlighted: false);
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final draggedPad = padsById[details.data];
        return draggedPad != null && draggedPad.folderId != folder.id;
      },
      onAcceptWithDetails: (details) => onPadDropped(details.data),
      builder: (context, candidateData, _) {
        return buildChip(highlighted: candidateData.isNotEmpty);
      },
    );
  }
}

int _columnCountForWidth(double width, GridDensity density) {
  final targetTileWidth = switch (density) {
    GridDensity.comfortable => 190.0,
    GridDensity.standard => 155.0,
    GridDensity.compact => 120.0,
  };
  final minCols = switch (density) {
    GridDensity.comfortable => 2,
    GridDensity.standard => 2,
    GridDensity.compact => 3,
  };
  final maxCols = switch (density) {
    GridDensity.comfortable => 5,
    GridDensity.standard => 6,
    GridDensity.compact => 8,
  };
  return (width / targetTileWidth).floor().clamp(minCols, maxCols);
}

double _tileHeightForDensity(GridDensity density, double textScale) {
  final baseExtent = switch (density) {
    GridDensity.comfortable => 156.0,
    GridDensity.standard => 136.0,
    GridDensity.compact => 116.0,
  };
  final extraForScale = (textScale - 1.0).clamp(0.0, 2.0) * 76.0;
  return baseExtent + extraForScale;
}
