import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Presents the Material 3 settings bottom sheet.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const SettingsSheet(),
  );
}

/// Scrollable Material 3 settings sheet for theme, dynamic color, grid density,
/// and global default fade/crossfade durations.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final libraryAsync = ref.watch(libraryControllerProvider);
    final settings =
        libraryAsync.asData?.value.settings ?? const BoardSettings();
    final controller = ref.read(libraryControllerProvider.notifier);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Settings',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text('Theme', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Dark'),
                  selected: settings.themeMode == AppThemeMode.dark,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(themeMode: AppThemeMode.dark),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Light'),
                  selected: settings.themeMode == AppThemeMode.light,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(themeMode: AppThemeMode.light),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('System'),
                  selected: settings.themeMode == AppThemeMode.system,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(themeMode: AppThemeMode.system),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dynamic color'),
              subtitle: const Text(
                'Use system wallpaper colors when supported',
              ),
              value: settings.useDynamicColor,
              onChanged: (enabled) {
                controller.updateSettings(
                  settings.copyWith(useDynamicColor: enabled),
                );
              },
            ),
            const Divider(height: 24),
            Text('Grid density', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Comfortable'),
                  selected: settings.gridDensity == GridDensity.comfortable,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(gridDensity: GridDensity.comfortable),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Standard'),
                  selected: settings.gridDensity == GridDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(gridDensity: GridDensity.standard),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Compact'),
                  selected: settings.gridDensity == GridDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    controller.updateSettings(
                      settings.copyWith(gridDensity: GridDensity.compact),
                    );
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Default fades', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _DurationSliderRow(
              label: 'Fade-in',
              semanticsLabel: 'Default fade-in duration',
              durationMs: settings.defaultFadeInMs,
              maxMs: 3000,
              onChanged: (ms) {
                controller.updateSettings(
                  settings.copyWith(defaultFadeInMs: ms),
                );
              },
            ),
            _DurationSliderRow(
              label: 'Fade-out',
              semanticsLabel: 'Default fade-out duration',
              durationMs: settings.defaultFadeOutMs,
              maxMs: 5000,
              onChanged: (ms) {
                controller.updateSettings(
                  settings.copyWith(defaultFadeOutMs: ms),
                );
              },
            ),
            _DurationSliderRow(
              label: 'Crossfade',
              semanticsLabel: 'Default crossfade duration',
              durationMs: settings.defaultCrossfadeMs,
              maxMs: 5000,
              onChanged: (ms) {
                controller.updateSettings(
                  settings.copyWith(defaultCrossfadeMs: ms),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationSliderRow extends StatelessWidget {
  const _DurationSliderRow({
    required this.label,
    required this.semanticsLabel,
    required this.durationMs,
    required this.maxMs,
    required this.onChanged,
  });

  final String label;
  final String semanticsLabel;
  final int durationMs;
  final int maxMs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedMs = durationMs.clamp(0, maxMs);
    final secondsText = '${(clampedMs / 1000).toStringAsFixed(1)} s';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
            const SizedBox(width: 8),
            Text(
              secondsText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Semantics(
          label: semanticsLabel,
          child: Slider(
            value: clampedMs.toDouble(),
            min: 0,
            max: maxMs.toDouble(),
            divisions: maxMs ~/ 100,
            label: secondsText,
            onChanged: (value) => onChanged((value / 100).round() * 100),
          ),
        ),
      ],
    );
  }
}
