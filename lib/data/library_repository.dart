import 'package:auraboard/data/demo_board.dart';
import 'package:auraboard/domain/models.dart';

/// Persistence contract for loading and saving the soundboard [SoundLibrary].
abstract interface class LibraryRepository {
  Future<SoundLibrary> load();
  Future<void> save(SoundLibrary library);
}

/// In-memory [LibraryRepository] that seeds the demo library on first load.
class InMemoryLibraryRepository implements LibraryRepository {
  SoundLibrary? _library;

  @override
  Future<SoundLibrary> load() async {
    return _library ??= createDemoLibrary();
  }

  @override
  Future<void> save(SoundLibrary library) async {
    _library = library;
  }
}
