import 'package:auraboard/app.dart';
import 'package:auraboard/data/file_library_repository.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final repository = FileLibraryRepository(directory: supportDir);
  runApp(
    ProviderScope(
      overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
      child: const AuraBoardApp(),
    ),
  );
}
