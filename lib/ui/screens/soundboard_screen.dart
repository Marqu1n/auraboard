import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:auraboard/ui/widgets/now_playing_bar.dart';
import 'package:auraboard/ui/widgets/pad_tile.dart';
import 'package:auraboard/ui/widgets/settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Primary Play-Mode soundboard screen with folder strip, responsive pad grid,
/// and persistent Now-Playing mixer bar.
class SoundboardScreen extends ConsumerStatefulWidget {
  const SoundboardScreen({super.key});

  @override
  ConsumerState<SoundboardScreen> createState() => _SoundboardScreenState();
}

class _SoundboardScreenState extends ConsumerState<SoundboardScreen> {
  String? _selectedFolderId;

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryControllerProvider);
    final playbackState = ref.watch(playbackControllerProvider);
    final mediaQuery = MediaQuery.of(context);
    final isShortViewport = mediaQuery.size.height < 420;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AuraBoard'),
        toolbarHeight: isShortViewport ? 48 : null,
        actions: <Widget>[
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

          if (folders.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
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
                      ChoiceChip(
                        label: Text(folders[i].name),
                        selected: folders[i].id == effectiveFolderId,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: isShortViewport ? 8 : 13,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedFolderId = folders[i].id;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
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
                    final spacing = density == GridDensity.compact ? 8.0 : 12.0;

                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        isShortViewport ? 4 : 8,
                        horizontalPadding,
                        isShortViewport ? 8 : 16,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisExtent: mainAxisExtent,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      itemCount: visiblePads.length,
                      itemBuilder: (context, index) {
                        final pad = visiblePads[index];
                        final voice = playbackState.activeByPad[pad.id];
                        return PadTile(
                          pad: pad,
                          voice: voice,
                          density: density,
                          onTap: () => playbackNotifier.tapPad(pad),
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
