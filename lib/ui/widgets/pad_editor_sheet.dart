import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:auraboard/ui/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Curated palette of tabletop RPG pad colors designed for dim-room legibility.
const List<({String name, int value})> padColorPalette =
    <({String name, int value})>[
      (name: 'Crimson', value: 0xFFB84A39),
      (name: 'Ember', value: 0xFFD96B27),
      (name: 'Hearth Gold', value: 0xFFC68A32),
      (name: 'Forest Emerald', value: 0xFF3A7D44),
      (name: 'Arcane Violet', value: 0xFF6A4C93),
      (name: 'Storm Blue', value: 0xFF3E6D8C),
      (name: 'Deep Slate', value: 0xFF4F5D75),
      (name: 'Blood Ruby', value: 0xFF9C3D3D),
      (name: 'Sunlit Ochre', value: 0xFFD4A738),
      (name: 'Teal Mist', value: 0xFF2A7B76),
      (name: 'Royal Indigo', value: 0xFF43509C),
      (name: 'Obsidian Plum', value: 0xFF7A4465),
    ];

/// Presents the Material 3 bottom sheet for editing an existing [SoundPad].
Future<void> showPadEditorSheet(BuildContext context, {required SoundPad pad}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PadEditorSheet(pad: pad),
  );
}

/// Scrollable Material 3 modal bottom sheet for editing pad appearance, audio
/// behavior, fade overrides, folder assignment, and deletion.
class PadEditorSheet extends ConsumerStatefulWidget {
  const PadEditorSheet({super.key, required this.pad});

  final SoundPad pad;

  @override
  ConsumerState<PadEditorSheet> createState() => _PadEditorSheetState();
}

class _PadEditorSheetState extends ConsumerState<PadEditorSheet> {
  late final TextEditingController _labelController;
  late int _colorValue;
  late PadIcon? _icon;
  late PadType _type;
  late double _volume;
  late RetriggerMode _retriggerMode;
  late String _folderId;
  late int? _fadeInMsOverride;
  late int? _fadeOutMsOverride;
  late int? _crossfadeMsOverride;
  String? _labelError;

  @override
  void initState() {
    super.initState();
    final pad = widget.pad;
    _labelController = TextEditingController(text: pad.label);
    _colorValue = pad.colorValue;
    _icon = pad.icon;
    _type = pad.type;
    _volume = pad.volume.clamp(0.0, 1.0);
    _retriggerMode = pad.retriggerMode;
    _folderId = pad.folderId;
    _fadeInMsOverride = pad.fadeInMsOverride;
    _fadeOutMsOverride = pad.fadeOutMsOverride;
    _crossfadeMsOverride = pad.crossfadeMsOverride;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final trimmed = _labelController.text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _labelError = 'Label cannot be empty';
      });
      return;
    }

    final folders = List<SoundFolder>.from(
      ref.read(libraryControllerProvider).asData?.value.folders ??
          const <SoundFolder>[],
    )..sort((a, b) => a.order.compareTo(b.order));
    final resolvedFolderId = folders.any((folder) => folder.id == _folderId)
        ? _folderId
        : (folders.isNotEmpty ? folders.first.id : _folderId);

    final updated = widget.pad.copyWith(
      label: trimmed,
      colorValue: _colorValue,
      icon: _icon,
      clearIcon: _icon == null,
      type: _type,
      volume: _volume,
      retriggerMode: _retriggerMode,
      folderId: resolvedFolderId,
      fadeInMsOverride: _fadeInMsOverride,
      clearFadeInMsOverride: _fadeInMsOverride == null,
      fadeOutMsOverride: _fadeOutMsOverride,
      clearFadeOutMsOverride: _fadeOutMsOverride == null,
      crossfadeMsOverride: _type == PadType.music ? _crossfadeMsOverride : null,
      clearCrossfadeMsOverride:
          _type != PadType.music || _crossfadeMsOverride == null,
    );

    await ref.read(libraryControllerProvider.notifier).updatePad(updated);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmAndDelete() async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.pad.label}"?'),
        content: const Text(
          'This removes the pad from your board and stops it if playing.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_delete_pad'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await ref.read(libraryControllerProvider.notifier).deletePad(widget.pad.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final library = ref.watch(libraryControllerProvider).asData?.value;
    final settings = library?.settings ?? const BoardSettings();
    final folders = List<SoundFolder>.from(
      library?.folders ?? const <SoundFolder>[],
    )..sort((a, b) => a.order.compareTo(b.order));

    final effectiveFolderId = folders.any((folder) => folder.id == _folderId)
        ? _folderId
        : (folders.isNotEmpty ? folders.first.id : _folderId);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Edit Pad',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('pad_editor_label'),
                controller: _labelController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Pad label',
                  border: const OutlineInputBorder(),
                  errorText: _labelError,
                ),
                onChanged: (_) {
                  if (_labelError != null) {
                    setState(() => _labelError = null);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text('Color', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (var i = 0; i < padColorPalette.length; i++)
                    _ColorSwatchButton(
                      key: Key('pad_color_$i'),
                      name: padColorPalette[i].name,
                      color: Color(padColorPalette[i].value),
                      selected: _colorValue == padColorPalette[i].value,
                      onTap: () => setState(
                        () => _colorValue = padColorPalette[i].value,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Icon (optional)', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _IconChoiceButton(
                    key: const Key('pad_icon_none'),
                    semanticsLabel: 'No icon',
                    selected: _icon == null,
                    accentColor: Color(_colorValue),
                    onTap: () => setState(() => _icon = null),
                    child: const Icon(Icons.block, size: 22),
                  ),
                  for (final iconOption in PadIcon.values)
                    _IconChoiceButton(
                      key: Key('pad_icon_${iconOption.name}'),
                      semanticsLabel: 'Icon ${iconOption.name}',
                      selected: _icon == iconOption,
                      accentColor: Color(_colorValue),
                      onTap: () => setState(() => _icon = iconOption),
                      child: Icon(iconForPad(iconOption), size: 22),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Pad type', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final typeOption in PadType.values)
                    ChoiceChip(
                      key: Key('pad_type_${typeOption.name}'),
                      label: Text(padTypeLabel(typeOption)),
                      selected: _type == typeOption,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(() => _type = typeOption),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      'Pad volume',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(_volume * 100).round()}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Semantics(
                label: 'Pad volume',
                child: Slider(
                  key: const Key('pad_editor_volume'),
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (value) => setState(() => _volume = value),
                ),
              ),
              if (_type == PadType.effect) ...<Widget>[
                const SizedBox(height: 8),
                Text('Retrigger behavior', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      key: const Key('pad_retrigger_restart'),
                      label: const Text('Restart'),
                      selected: _retriggerMode == RetriggerMode.restart,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) => setState(
                        () => _retriggerMode = RetriggerMode.restart,
                      ),
                    ),
                    ChoiceChip(
                      key: const Key('pad_retrigger_layer'),
                      label: const Text('Layer'),
                      selected: _retriggerMode == RetriggerMode.layer,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) =>
                          setState(() => _retriggerMode = RetriggerMode.layer),
                    ),
                  ],
                ),
              ],
              const Divider(height: 28),
              Text('Fade overrides', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              _FadeOverrideControl(
                label: 'Fade-in override',
                valueMs: _fadeInMsOverride,
                defaultMs: settings.defaultFadeInMs,
                maxMs: 3000,
                onChanged: (value) => setState(() => _fadeInMsOverride = value),
              ),
              _FadeOverrideControl(
                label: 'Fade-out override',
                valueMs: _fadeOutMsOverride,
                defaultMs: settings.defaultFadeOutMs,
                maxMs: 5000,
                onChanged: (value) =>
                    setState(() => _fadeOutMsOverride = value),
              ),
              if (_type == PadType.music)
                _FadeOverrideControl(
                  label: 'Crossfade override',
                  valueMs: _crossfadeMsOverride,
                  defaultMs: settings.defaultCrossfadeMs,
                  maxMs: 5000,
                  onChanged: (value) =>
                      setState(() => _crossfadeMsOverride = value),
                ),
              if (folders.isNotEmpty) ...<Widget>[
                const Divider(height: 28),
                Text('Folder', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('pad_editor_folder'),
                  initialValue: effectiveFolderId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Move to folder',
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final folder in folders)
                      DropdownMenuItem<String>(
                        value: folder.id,
                        child: Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _folderId = value);
                    }
                  },
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('pad_editor_delete'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                    ),
                    onPressed: _confirmAndDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                  FilledButton.icon(
                    key: const Key('pad_editor_save'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Color $name',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 20, color: foreground)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconChoiceButton extends StatelessWidget {
  const _IconChoiceButton({
    super.key,
    required this.semanticsLabel,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  final String semanticsLabel;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                accentColor.withAlpha(56),
                colorScheme.surfaceContainerHighest,
              )
            : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? accentColor : colorScheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? accentColor : colorScheme.onSurfaceVariant,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FadeOverrideControl extends StatelessWidget {
  const _FadeOverrideControl({
    required this.label,
    required this.valueMs,
    required this.defaultMs,
    required this.maxMs,
    required this.onChanged,
  });

  final String label;
  final int? valueMs;
  final int defaultMs;
  final int maxMs;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isEnabled = valueMs != null;
    final effectiveMs = (valueMs ?? defaultMs).clamp(0, maxMs);
    final secondsLabel = '${(effectiveMs / 1000).toStringAsFixed(1)} s';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(
            isEnabled
                ? 'Custom: $secondsLabel'
                : 'Using default (${(defaultMs / 1000).toStringAsFixed(1)} s)',
          ),
          value: isEnabled,
          onChanged: (enabled) =>
              onChanged(enabled ? defaultMs.clamp(0, maxMs) : null),
        ),
        if (isEnabled)
          Semantics(
            label: '$label duration',
            child: Slider(
              value: effectiveMs.toDouble(),
              min: 0,
              max: maxMs.toDouble(),
              divisions: maxMs ~/ 100,
              label: secondsLabel,
              onChanged: (value) => onChanged((value / 100).round() * 100),
            ),
          ),
      ],
    );
  }
}
