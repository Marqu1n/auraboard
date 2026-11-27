import 'package:auraboard/data/backup_service.dart';
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
/// global default fade/crossfade durations, and offline backup transfer.
class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
  bool _isBackupBusy = false;

  Future<void> _handleExportBackup() async {
    if (_isBackupBusy) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isBackupBusy = true);
    try {
      final bytes = await ref
          .read(libraryControllerProvider.notifier)
          .exportBackup();
      final saved = await ref
          .read(filePickerGatewayProvider)
          .saveBackupBytes(
            suggestedFileName: 'auraboard_backup.auraboard',
            bytes: bytes,
          );
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Backup exported successfully.'
                  : 'Backup export canceled.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Backup export failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isBackupBusy = false);
      }
    }
  }

  Future<void> _handleImportBackup() async {
    if (_isBackupBusy) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _isBackupBusy = true);
    try {
      final archiveBytes = await ref
          .read(filePickerGatewayProvider)
          .pickBackupBytes();
      if (archiveBytes == null || !mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore backup?'),
          content: const Text(
            'Importing this backup will stop all playing audio and replace '
            'your current folders, pads, and settings.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm_import_backup'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) {
        return;
      }

      // Validate and restore backup BEFORE stopping playback so corrupt or
      // invalid archives never interrupt an active session.
      await ref
          .read(libraryControllerProvider.notifier)
          .importBackup(archiveBytes);
      if (mounted) {
        await ref.read(playbackControllerProvider.notifier).stopAll();
      }
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Backup restored successfully.')),
        );
    } on BackupException catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Backup import failed: ${error.message}')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Backup import failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isBackupBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
            const Divider(height: 24),
            Text('Session', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('keep_screen_awake_switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep screen awake'),
              subtitle: const Text(
                'Prevent the screen from dimming or locking during sessions.',
              ),
              value: settings.keepScreenAwake,
              onChanged: (enabled) {
                controller.updateSettings(
                  settings.copyWith(keepScreenAwake: enabled),
                );
              },
            ),
            const Divider(height: 24),
            Text(
              'Backup & Transfer (Offline)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Export or restore your board and imported audio as a single offline file.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('export_backup_button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: _isBackupBusy ? null : _handleExportBackup,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export backup'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('import_backup_button'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: _isBackupBusy ? null : _handleImportBackup,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import backup'),
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
