import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:auraboard/ui/screens/soundboard_screen.dart';
import 'package:auraboard/ui/theme/app_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Root Material 3 application widget for AuraBoard.
class AuraBoardApp extends ConsumerWidget {
  const AuraBoardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryControllerProvider);
    final settings =
        libraryAsync.asData?.value.settings ?? const BoardSettings();

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'AuraBoard',
          debugShowCheckedModeBanner: false,
          themeMode: themeModeFor(settings.themeMode),
          theme: buildAppTheme(
            settings: settings,
            brightness: Brightness.light,
            dynamicColorScheme: lightDynamic,
          ),
          darkTheme: buildAppTheme(
            settings: settings,
            brightness: Brightness.dark,
            dynamicColorScheme: darkDynamic,
          ),
          home: const SoundboardScreen(),
        );
      },
    );
  }
}
