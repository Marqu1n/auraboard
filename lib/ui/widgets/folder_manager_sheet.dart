import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Prompts for a folder name to create a new folder or rename an existing one.
Future<String?> showFolderNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
    ),
  );
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _errorText = 'Folder name cannot be empty';
      });
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: TextField(
          key: const Key('folder_name_input'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Folder name',
            hintText: 'e.g. Boss Fight',
            border: const OutlineInputBorder(),
            errorText: _errorText,
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('folder_dialog_confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Presents the Material 3 bottom sheet for managing folders (reorder, rename,
/// and delete).
Future<void> showFolderManagerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const FolderManagerSheet(),
  );
}

/// Scrollable Material 3 sheet listing all folders in order with controls to
/// reorder, rename, and delete folders.
class FolderManagerSheet extends ConsumerWidget {
  const FolderManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final libraryAsync = ref.watch(libraryControllerProvider);
    final library = libraryAsync.asData?.value;

    if (library == null) {
      return const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final folders = List<SoundFolder>.from(library.folders)
      ..sort((a, b) => a.order.compareTo(b.order));
    final controller = ref.read(libraryControllerProvider.notifier);
    final canDelete = folders.length > 1;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Manage Folders',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < folders.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: 8),
              _FolderRowCard(
                folder: folders[index],
                padCount: library.pads
                    .where((pad) => pad.folderId == folders[index].id)
                    .length,
                canMoveUp: index > 0,
                canMoveDown: index < folders.length - 1,
                canDelete: canDelete,
                onMoveUp: () => controller.reorderFolders(index, index - 1),
                onMoveDown: () => controller.reorderFolders(index, index + 1),
                onRename: () async {
                  final renamed = await showFolderNameDialog(
                    context,
                    title: 'Rename Folder',
                    confirmLabel: 'Save',
                    initialValue: folders[index].name,
                  );
                  if (renamed != null) {
                    await controller.renameFolder(folders[index].id, renamed);
                  }
                },
                onDelete: () async {
                  final otherFolders = folders
                      .where((candidate) => candidate.id != folders[index].id)
                      .toList();
                  final padCount = library.pads
                      .where((pad) => pad.folderId == folders[index].id)
                      .length;
                  final decision = await showDialog<_DeleteFolderDecision>(
                    context: context,
                    builder: (_) => _DeleteFolderDialog(
                      folder: folders[index],
                      padCount: padCount,
                      otherFolders: otherFolders,
                    ),
                  );
                  if (decision != null && decision.confirmed) {
                    await controller.deleteFolder(
                      folders[index].id,
                      movePadsToFolderId: decision.movePadsToFolderId,
                    );
                  }
                },
              ),
            ],
            if (!canDelete) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'At least one folder must remain on the soundboard.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FolderRowCard extends StatelessWidget {
  const _FolderRowCard({
    required this.folder,
    required this.padCount,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRename,
    required this.onDelete,
  });

  final SoundFolder folder;
  final int padCount;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final padCountLabel = padCount == 1 ? '1 pad' : '$padCount pads';

    return Card(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        folder.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        padCountLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                IconButton(
                  key: Key('move_folder_up_${folder.id}'),
                  tooltip: 'Move ${folder.name} up',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: canMoveUp ? onMoveUp : null,
                ),
                IconButton(
                  key: Key('move_folder_down_${folder.id}'),
                  tooltip: 'Move ${folder.name} down',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: canMoveDown ? onMoveDown : null,
                ),
                IconButton(
                  key: Key('rename_folder_${folder.id}'),
                  tooltip: 'Rename ${folder.name}',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onRename,
                ),
                IconButton(
                  key: Key('delete_folder_${folder.id}'),
                  tooltip: 'Delete ${folder.name}',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(
                    Icons.delete_outline,
                    color: canDelete ? colorScheme.error : null,
                  ),
                  onPressed: canDelete ? onDelete : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteFolderDecision {
  const _DeleteFolderDecision({
    required this.confirmed,
    this.movePadsToFolderId,
  });

  final bool confirmed;
  final String? movePadsToFolderId;
}

class _DeleteFolderDialog extends StatefulWidget {
  const _DeleteFolderDialog({
    required this.folder,
    required this.padCount,
    required this.otherFolders,
  });

  final SoundFolder folder;
  final int padCount;
  final List<SoundFolder> otherFolders;

  @override
  State<_DeleteFolderDialog> createState() => _DeleteFolderDialogState();
}

class _DeleteFolderDialogState extends State<_DeleteFolderDialog> {
  String? _movePadsToFolderId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPads = widget.padCount > 0 && widget.otherFolders.isNotEmpty;

    return AlertDialog(
      title: Text('Delete "${widget.folder.name}"?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              hasPads
                  ? 'This folder contains ${widget.padCount} '
                        '${widget.padCount == 1 ? 'pad' : 'pads'}. '
                        'Choose whether to delete them or move them to another folder.'
                  : 'This empty folder will be removed.',
            ),
            if (hasPads) ...<Widget>[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('delete_folder_move_target'),
                initialValue: _movePadsToFolderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Pads in this folder',
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'Delete pads',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final other in widget.otherFolders)
                    DropdownMenuItem<String?>(
                      value: other.id,
                      child: Text(
                        'Move to ${other.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _movePadsToFolderId = value),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const _DeleteFolderDecision(confirmed: false)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm_delete_folder'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(
            _DeleteFolderDecision(
              confirmed: true,
              movePadsToFolderId: _movePadsToFolderId,
            ),
          ),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
