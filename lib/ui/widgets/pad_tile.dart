import 'package:auraboard/domain/models.dart';
import 'package:auraboard/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Interactive sound pad card with unmistakable visual and semantic states
/// for dim-room, 1-second-glance operation.
class PadTile extends StatelessWidget {
  const PadTile({
    super.key,
    required this.pad,
    required this.voice,
    required this.density,
    required this.onTap,
    this.isEditMode = false,
    this.isDropTarget = false,
  });

  final SoundPad pad;
  final ActiveVoiceState? voice;
  final GridDensity density;
  final VoidCallback onTap;
  final bool isEditMode;
  final bool isDropTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14.0) / 14.0;

    final phase = voice?.phase ?? PadPlaybackPhase.idle;
    final isLooping = isLoopingPadType(pad.type);
    final activeLayerCount = voice?.activeLayerCount ?? 0;
    final showLayerBadge =
        activeLayerCount > 1 &&
        phase != PadPlaybackPhase.idle &&
        phase != PadPlaybackPhase.error;
    final showProgress =
        pad.type == PadType.effect &&
        (phase == PadPlaybackPhase.playing ||
            phase == PadPlaybackPhase.fadingIn);

    final durationMs = voice?.duration.inMilliseconds ?? 0;
    final positionMs = voice?.position.inMilliseconds ?? 0;
    final progress = durationMs > 0
        ? (positionMs / durationMs).clamp(0.0, 1.0)
        : 0.0;

    final accentColor = Color(pad.colorValue);
    final style = _resolveStyle(
      phase: phase,
      accentColor: accentColor,
      colorScheme: colorScheme,
    );

    final statusText = phaseLabel(phase);
    final semanticParts = <String>[
      if (isEditMode) 'Edit',
      pad.label,
      padTypeLabel(pad.type),
      if (isLooping) 'Loop',
      statusText,
      if (showLayerBadge) '$activeLayerCount layers',
    ];

    final isCompact = density == GridDensity.compact;
    final contentPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 8 : 12,
      vertical: isCompact ? 6 : 10,
    );
    final iconSize = isCompact ? 20.0 : 22.0;
    final labelMaxLines = (isCompact && textScale >= 1.5) ? 1 : 2;
    final padIcon = pad.icon;
    final borderColor = isDropTarget
        ? colorScheme.primary
        : (isEditMode && phase == PadPlaybackPhase.idle
              ? colorScheme.outline
              : style.borderColor);
    final borderWidth = isDropTarget
        ? 3.0
        : (isEditMode && phase == PadPlaybackPhase.idle
              ? 1.5
              : style.borderWidth);

    return Semantics(
      button: true,
      enabled: true,
      onTap: onTap,
      label: semanticParts.join(', '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Card(
          margin: EdgeInsets.zero,
          color: style.surfaceColor,
          elevation: style.elevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: style.accentBarHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: style.accentBarColor),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (padIcon != null) ...<Widget>[
                              Icon(
                                iconForPad(padIcon),
                                size: iconSize,
                                color: style.padIconColor,
                              ),
                              if (isLooping) const SizedBox(width: 6),
                            ],
                            if (isLooping)
                              Icon(
                                Icons.repeat,
                                size: 16,
                                color: style.loopIconColor,
                              ),
                            if (showLayerBadge) ...<Widget>[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '×$activeLayerCount',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color:
                                                colorScheme.onTertiaryContainer,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ] else if (isEditMode) ...<Widget>[
                              const Spacer(),
                              Icon(
                                Icons.drag_indicator,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              pad.label,
                              maxLines: labelMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (isCompact
                                          ? theme.textTheme.titleSmall
                                          : theme.textTheme.titleMedium)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: style.labelColor,
                                      ),
                            ),
                          ),
                        ),
                        if (phase != PadPlaybackPhase.idle) ...<Widget>[
                          const SizedBox(height: 4),
                          _PhaseStatusBadge(
                            phase: phase,
                            label: statusText,
                            backgroundColor: style.badgeBackground,
                            foregroundColor: style.badgeForeground,
                            bold: phase == PadPlaybackPhase.playing,
                          ),
                        ],
                        if (showProgress) ...<Widget>[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              color: accentColor,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseStatusBadge extends StatelessWidget {
  const _PhaseStatusBadge({
    required this.phase,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.bold,
  });

  final PadPlaybackPhase phase;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_phaseIcon(phase), size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _phaseIcon(PadPlaybackPhase phase) {
  return switch (phase) {
    PadPlaybackPhase.idle => Icons.stop_circle_outlined,
    PadPlaybackPhase.fadingIn => Icons.trending_up,
    PadPlaybackPhase.playing => Icons.graphic_eq,
    PadPlaybackPhase.fadingOut => Icons.trending_down,
    PadPlaybackPhase.error => Icons.error_outline,
  };
}

class _PadVisualStyle {
  const _PadVisualStyle({
    required this.surfaceColor,
    required this.borderColor,
    required this.borderWidth,
    required this.elevation,
    required this.accentBarColor,
    required this.accentBarHeight,
    required this.padIconColor,
    required this.loopIconColor,
    required this.labelColor,
    required this.badgeBackground,
    required this.badgeForeground,
  });

  final Color surfaceColor;
  final Color borderColor;
  final double borderWidth;
  final double elevation;
  final Color accentBarColor;
  final double accentBarHeight;
  final Color padIconColor;
  final Color loopIconColor;
  final Color labelColor;
  final Color badgeBackground;
  final Color badgeForeground;
}

_PadVisualStyle _resolveStyle({
  required PadPlaybackPhase phase,
  required Color accentColor,
  required ColorScheme colorScheme,
}) {
  return switch (phase) {
    PadPlaybackPhase.idle => _PadVisualStyle(
      surfaceColor: colorScheme.surfaceContainerLow,
      borderColor: colorScheme.outlineVariant,
      borderWidth: 1.0,
      elevation: 1.0,
      accentBarColor: accentColor.withAlpha(180),
      accentBarHeight: 4.0,
      padIconColor: accentColor,
      loopIconColor: colorScheme.onSurfaceVariant,
      labelColor: colorScheme.onSurface,
      badgeBackground: colorScheme.surfaceContainerHighest,
      badgeForeground: colorScheme.onSurfaceVariant,
    ),
    PadPlaybackPhase.fadingIn => _PadVisualStyle(
      surfaceColor: Color.alphaBlend(
        accentColor.withAlpha(38),
        colorScheme.surfaceContainerHigh,
      ),
      borderColor: accentColor.withAlpha(220),
      borderWidth: 2.0,
      elevation: 3.0,
      accentBarColor: accentColor,
      accentBarHeight: 4.0,
      padIconColor: accentColor,
      loopIconColor: colorScheme.onSurface,
      labelColor: colorScheme.onSurface,
      badgeBackground: colorScheme.secondaryContainer,
      badgeForeground: colorScheme.onSecondaryContainer,
    ),
    PadPlaybackPhase.playing => _PadVisualStyle(
      surfaceColor: Color.alphaBlend(
        accentColor.withAlpha(70),
        colorScheme.surfaceContainerHigh,
      ),
      borderColor: accentColor,
      borderWidth: 3.0,
      elevation: 5.0,
      accentBarColor: accentColor,
      accentBarHeight: 5.0,
      padIconColor: accentColor,
      loopIconColor: colorScheme.onSurface,
      labelColor: colorScheme.onSurface,
      badgeBackground: colorScheme.primaryContainer,
      badgeForeground: colorScheme.onPrimaryContainer,
    ),
    PadPlaybackPhase.fadingOut => _PadVisualStyle(
      surfaceColor: colorScheme.surfaceContainer,
      borderColor: colorScheme.outline,
      borderWidth: 1.5,
      elevation: 1.0,
      accentBarColor: colorScheme.outline,
      accentBarHeight: 4.0,
      padIconColor: colorScheme.onSurfaceVariant,
      loopIconColor: colorScheme.onSurfaceVariant,
      labelColor: colorScheme.onSurfaceVariant,
      badgeBackground: colorScheme.surfaceContainerHighest,
      badgeForeground: colorScheme.onSurfaceVariant,
    ),
    PadPlaybackPhase.error => _PadVisualStyle(
      surfaceColor: colorScheme.errorContainer,
      borderColor: colorScheme.error,
      borderWidth: 2.5,
      elevation: 2.0,
      accentBarColor: colorScheme.error,
      accentBarHeight: 4.0,
      padIconColor: colorScheme.error,
      loopIconColor: colorScheme.onErrorContainer,
      labelColor: colorScheme.onErrorContainer,
      badgeBackground: colorScheme.error,
      badgeForeground: colorScheme.onError,
    ),
  };
}
