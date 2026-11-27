import 'package:auraboard/domain/models.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

/// Maps domain [AppThemeMode] to Material [ThemeMode].
ThemeMode themeModeFor(AppThemeMode mode) {
  return switch (mode) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
}

/// Builds the Material Design 3 [ThemeData] for [brightness], honoring
/// [BoardSettings.useDynamicColor] when an OS [dynamicColorScheme] is supplied.
ThemeData buildAppTheme({
  required BoardSettings settings,
  required Brightness brightness,
  ColorScheme? dynamicColorScheme,
}) {
  final ColorScheme colorScheme;
  if (settings.useDynamicColor && dynamicColorScheme != null) {
    colorScheme = dynamicColorScheme.harmonized();
  } else {
    colorScheme = ColorScheme.fromSeed(
      seedColor: Color(settings.seedColorValue),
      brightness: brightness,
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
    ),
  );
}

/// Maps offline [PadIcon] identifiers to bundled Material [IconData].
IconData iconForPad(PadIcon icon) {
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

/// Human-readable label for a [PadType].
String padTypeLabel(PadType type) {
  return switch (type) {
    PadType.effect => 'Effect',
    PadType.music => 'Music',
    PadType.ambience => 'Ambience',
  };
}

/// Human-readable status text for a [PadPlaybackPhase].
String phaseLabel(PadPlaybackPhase phase) {
  return switch (phase) {
    PadPlaybackPhase.idle => 'Idle',
    PadPlaybackPhase.fadingIn => 'Fading in',
    PadPlaybackPhase.playing => 'Playing',
    PadPlaybackPhase.fadingOut => 'Fading out',
    PadPlaybackPhase.error => 'Error',
  };
}

/// Whether [type] loops continuously until stopped.
bool isLoopingPadType(PadType type) {
  return type == PadType.music || type == PadType.ambience;
}
