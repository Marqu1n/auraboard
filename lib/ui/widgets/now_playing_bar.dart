import 'dart:math' as math;

import 'package:auraboard/domain/models.dart';
import 'package:auraboard/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Paired [SoundPad] metadata and its live [ActiveVoiceState] for the
/// persistent Now-Playing mixer bar.
class ActiveSoundEntry {
  const ActiveSoundEntry({required this.pad, required this.voice});

  final SoundPad pad;
  final ActiveVoiceState voice;
}

/// Persistent bottom playback panel displaying active voices across all folders
/// alongside master volume and a prominent Stop All control.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    super.key,
    required this.activeEntries,
    required this.masterVolume,
    required this.onMasterVolumeChanged,
    required this.onPadVolumeChanged,
    required this.onStopPad,
    required this.onStopAll,
  });

  final List<ActiveSoundEntry> activeEntries;
  final double masterVolume;
  final ValueChanged<double> onMasterVolumeChanged;
  final void Function(String padId, double volume) onPadVolumeChanged;
  final ValueChanged<String> onStopPad;
  final VoidCallback onStopAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final textScale = mediaQuery.textScaler.scale(14.0) / 14.0;
    final isShortViewport = screenHeight < 420;
    final hasActiveVoices = activeEntries.isNotEmpty;

    final maxListHeight = isShortViewport
        ? math.min(96.0, screenHeight * 0.26)
        : math.min(180.0, screenHeight * 0.28);

    return Material(
      color: colorScheme.surfaceContainer,
      elevation: 6,
      surfaceTintColor: colorScheme.surfaceTint,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasActiveVoices) ...<Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxListHeight),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isShortViewport ? 2 : 4,
                    ),
                    itemCount: activeEntries.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withAlpha(110),
                    ),
                    itemBuilder: (context, index) {
                      final entry = activeEntries[index];
                      return _ActiveSoundRow(
                        entry: entry,
                        onVolumeChanged: (value) =>
                            onPadVolumeChanged(entry.pad.id, value),
                        onStop: () => onStopPad(entry.pad.id),
                      );
                    },
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
              ],
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isShortViewport ? 4 : 6,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showLeadingIcon =
                        constraints.maxWidth >= 340 &&
                        !(constraints.maxWidth < 400 && textScale >= 1.75);
                    final maxStopAllWidth = (constraints.maxWidth * 0.46).clamp(
                      96.0,
                      220.0,
                    );
                    final stopAllPadding = constraints.maxWidth < 400
                        ? const EdgeInsets.symmetric(horizontal: 10)
                        : const EdgeInsets.symmetric(horizontal: 14);

                    return Row(
                      children: <Widget>[
                        if (showLeadingIcon) ...<Widget>[
                          ExcludeSemantics(
                            child: Icon(
                              masterVolume <= 0.01
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Semantics(
                            label: 'Master volume',
                            child: Slider(
                              key: const Key('master_volume_slider'),
                              value: masterVolume.clamp(0.0, 1.0),
                              onChanged: onMasterVolumeChanged,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                            maxWidth: maxStopAllWidth,
                          ),
                          child: Semantics(
                            button: true,
                            enabled: true,
                            onTap: onStopAll,
                            label: 'Stop all sounds',
                            excludeSemantics: true,
                            child: FilledButton.tonalIcon(
                              key: const Key('stop_all_button'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: stopAllPadding,
                                backgroundColor: hasActiveVoices
                                    ? colorScheme.errorContainer
                                    : colorScheme.surfaceContainerHighest,
                                foregroundColor: hasActiveVoices
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              onPressed: onStopAll,
                              icon: const Icon(Icons.stop_rounded, size: 20),
                              label: const Text(
                                'Stop All',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSoundRow extends StatelessWidget {
  const _ActiveSoundRow({
    required this.entry,
    required this.onVolumeChanged,
    required this.onStop,
  });

  final ActiveSoundEntry entry;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pad = entry.pad;
    final voice = entry.voice;
    final isLooping = isLoopingPadType(pad.type);
    final accentColor = Color(pad.colorValue);
    final isFadingOut = voice.phase == PadPlaybackPhase.fadingOut;

    final phaseIcon = switch (voice.phase) {
      PadPlaybackPhase.fadingIn => Icons.trending_up,
      PadPlaybackPhase.fadingOut => Icons.trending_down,
      PadPlaybackPhase.playing => Icons.graphic_eq,
      PadPlaybackPhase.idle => Icons.stop_circle_outlined,
      PadPlaybackPhase.error => Icons.error_outline,
    };

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            phaseIcon,
            size: 18,
            color: isFadingOut ? colorScheme.onSurfaceVariant : accentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Semantics(
            label:
                'Active: ${phaseLabel(voice.phase)}'
                '${isLooping ? ', Looping' : ''}, ${pad.label}',
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    pad.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isFadingOut
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isLooping) ...<Widget>[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.repeat,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Semantics(
            label: 'Volume for ${pad.label}',
            child: Slider(
              key: Key('now_playing_volume_${pad.id}'),
              value: voice.currentVolume.clamp(0.0, 1.0),
              onChanged: onVolumeChanged,
            ),
          ),
        ),
        IconButton(
          key: Key('now_playing_stop_${pad.id}'),
          tooltip: 'Stop ${pad.label}',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.stop_circle_outlined),
          onPressed: onStop,
        ),
      ],
    );
  }
}
