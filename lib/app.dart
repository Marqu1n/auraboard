import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Color _defaultSeedColor = Color(0xFFD4882A);

/// Root Material 3 application widget for AuraBoard.
class AuraBoardApp extends ConsumerWidget {
  const AuraBoardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryControllerProvider);
    final settings = libraryAsync.asData?.value.settings;
    final seedColor = settings != null
        ? Color(settings.seedColorValue)
        : _defaultSeedColor;
    final themeMode = switch (settings?.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.dark || null => ThemeMode.dark,
    };

    return MaterialApp(
      title: 'AuraBoard',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const _AuraBoardHomeScreen(),
    );
  }
}

class _AuraBoardHomeScreen extends ConsumerStatefulWidget {
  const _AuraBoardHomeScreen();

  @override
  ConsumerState<_AuraBoardHomeScreen> createState() =>
      _AuraBoardHomeScreenState();
}

class _AuraBoardHomeScreenState extends ConsumerState<_AuraBoardHomeScreen> {
  String? _selectedFolderId;

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(libraryControllerProvider);
    final playbackState = ref.watch(playbackControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AuraBoard')),
      body: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Failed to load soundboard: $error')),
        data: (library) {
          final folders = List<SoundFolder>.from(library.folders)
            ..sort((a, b) => a.order.compareTo(b.order));

          if (folders.isEmpty) {
            return const Center(child: Text('No folders available'));
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 60,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: folders.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final folder = folders[index];
                    final selected = folder.id == effectiveFolderId;
                    return ChoiceChip(
                      label: Text(folder.name),
                      selected: selected,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) {
                        setState(() {
                          _selectedFolderId = folder.id;
                        });
                      },
                    );
                  },
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisExtent: 140,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visiblePads.length,
                  itemBuilder: (context, index) {
                    final pad = visiblePads[index];
                    final phase = playbackState.phaseForPad(pad.id);
                    return _SoundPadCard(
                      pad: pad,
                      phase: phase,
                      onTap: () {
                        ref
                            .read(playbackControllerProvider.notifier)
                            .tapPad(pad);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SoundPadCard extends StatelessWidget {
  const _SoundPadCard({
    required this.pad,
    required this.phase,
    required this.onTap,
  });

  final SoundPad pad;
  final PadPlaybackPhase phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusLabel = _statusLabel(phase);
    final isActive =
        phase == PadPlaybackPhase.playing || phase == PadPlaybackPhase.fadingIn;
    final isError = phase == PadPlaybackPhase.error;
    final accentColor = Color(pad.colorValue);

    final borderColor = isError
        ? colorScheme.error
        : isActive
        ? accentColor
        : colorScheme.outlineVariant;

    final surfaceColor = isError
        ? colorScheme.errorContainer
        : isActive
        ? Color.alphaBlend(
            accentColor.withAlpha(56),
            colorScheme.surfaceContainerHigh,
          )
        : colorScheme.surfaceContainerLow;

    return Semantics(
      button: true,
      label: '${pad.label}, $statusLabel',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Card(
          margin: EdgeInsets.zero,
          color: surfaceColor,
          elevation: isActive ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: isActive ? 2.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Icon(
                        _iconForPad(pad.icon),
                        size: 24,
                        color: isError ? colorScheme.error : accentColor,
                      ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? colorScheme.primaryContainer
                                : isError
                                ? colorScheme.error
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                _statusIcon(phase),
                                size: 14,
                                color: isError
                                    ? colorScheme.onError
                                    : isActive
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  statusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isError
                                        ? colorScheme.onError
                                        : isActive
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    pad.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(PadPlaybackPhase phase) {
  return switch (phase) {
    PadPlaybackPhase.idle => 'Idle',
    PadPlaybackPhase.fadingIn => 'Fading in',
    PadPlaybackPhase.playing => 'Playing',
    PadPlaybackPhase.fadingOut => 'Fading out',
    PadPlaybackPhase.error => 'Error',
  };
}

IconData _statusIcon(PadPlaybackPhase phase) {
  return switch (phase) {
    PadPlaybackPhase.idle => Icons.stop_circle_outlined,
    PadPlaybackPhase.fadingIn => Icons.trending_up,
    PadPlaybackPhase.playing => Icons.graphic_eq,
    PadPlaybackPhase.fadingOut => Icons.trending_down,
    PadPlaybackPhase.error => Icons.error_outline,
  };
}

IconData _iconForPad(PadIcon icon) {
  return switch (icon) {
    PadIcon.sword => Icons.hardware,
    PadIcon.fire => Icons.local_fire_department,
    PadIcon.shield => Icons.shield,
    PadIcon.music => Icons.music_note,
    PadIcon.drum => Icons.album,
    PadIcon.rain => Icons.water_drop,
    PadIcon.wind => Icons.air,
    PadIcon.tavern => Icons.local_bar,
    PadIcon.skull => Icons.dangerous,
    PadIcon.magic => Icons.auto_awesome,
    PadIcon.bell => Icons.notifications_active,
    PadIcon.door => Icons.door_front_door,
    PadIcon.monster => Icons.pets,
    PadIcon.camp => Icons.cabin,
    PadIcon.bolt => Icons.bolt,
    PadIcon.wave => Icons.waves,
  };
}
