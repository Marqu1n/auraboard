/// Behavioral category of a sound pad.
enum PadType { effect, music, ambience }

/// Behavior when a playing one-shot effect pad is tapped again.
enum RetriggerMode { restart, layer }

/// Observable playback lifecycle state for a sound pad.
enum PadPlaybackPhase { idle, fadingIn, playing, fadingOut, error }

/// Offline-bundled semantic icon identifier for a sound pad.
enum PadIcon {
  sword,
  fire,
  shield,
  music,
  drum,
  rain,
  wind,
  tavern,
  skull,
  magic,
  bell,
  door,
  monster,
  camp,
  bolt,
  wave,
}

/// Preferred pad grid density on the soundboard screen.
enum GridDensity { comfortable, standard, compact }

/// Application theme preference.
enum AppThemeMode { dark, light, system }

/// Named folder organizing pads on the soundboard.
class SoundFolder {
  const SoundFolder({
    required this.id,
    required this.name,
    required this.order,
  });

  final String id;
  final String name;
  final int order;

  SoundFolder copyWith({String? id, String? name, int? order}) {
    return SoundFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'name': name, 'order': order};
  }

  factory SoundFolder.fromJson(Map<String, dynamic> json) {
    return SoundFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      order: (json['order'] as num).toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SoundFolder &&
            other.id == id &&
            other.name == name &&
            other.order == order;
  }

  @override
  int get hashCode => Object.hash(id, name, order);

  @override
  String toString() => 'SoundFolder(id: $id, name: $name, order: $order)';
}

/// Configuration for a single playable pad on the soundboard.
class SoundPad {
  const SoundPad({
    required this.id,
    required this.folderId,
    required this.label,
    required this.colorValue,
    required this.icon,
    required this.audioPath,
    this.isAsset = false,
    required this.type,
    this.volume = 1.0,
    this.retriggerMode = RetriggerMode.restart,
    this.fadeInMsOverride,
    this.fadeOutMsOverride,
    this.crossfadeMsOverride,
    required this.order,
  });

  final String id;
  final String folderId;
  final String label;
  final int colorValue;
  final PadIcon icon;
  final String audioPath;
  final bool isAsset;
  final PadType type;
  final double volume;
  final RetriggerMode retriggerMode;
  final int? fadeInMsOverride;
  final int? fadeOutMsOverride;
  final int? crossfadeMsOverride;
  final int order;

  SoundPad copyWith({
    String? id,
    String? folderId,
    String? label,
    int? colorValue,
    PadIcon? icon,
    String? audioPath,
    bool? isAsset,
    PadType? type,
    double? volume,
    RetriggerMode? retriggerMode,
    int? fadeInMsOverride,
    bool clearFadeInMsOverride = false,
    int? fadeOutMsOverride,
    bool clearFadeOutMsOverride = false,
    int? crossfadeMsOverride,
    bool clearCrossfadeMsOverride = false,
    int? order,
  }) {
    return SoundPad(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      label: label ?? this.label,
      colorValue: colorValue ?? this.colorValue,
      icon: icon ?? this.icon,
      audioPath: audioPath ?? this.audioPath,
      isAsset: isAsset ?? this.isAsset,
      type: type ?? this.type,
      volume: volume ?? this.volume,
      retriggerMode: retriggerMode ?? this.retriggerMode,
      fadeInMsOverride: clearFadeInMsOverride
          ? null
          : (fadeInMsOverride ?? this.fadeInMsOverride),
      fadeOutMsOverride: clearFadeOutMsOverride
          ? null
          : (fadeOutMsOverride ?? this.fadeOutMsOverride),
      crossfadeMsOverride: clearCrossfadeMsOverride
          ? null
          : (crossfadeMsOverride ?? this.crossfadeMsOverride),
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'folderId': folderId,
      'label': label,
      'colorValue': colorValue,
      'icon': icon.name,
      'audioPath': audioPath,
      'isAsset': isAsset,
      'type': type.name,
      'volume': volume,
      'retriggerMode': retriggerMode.name,
      'fadeInMsOverride': fadeInMsOverride,
      'fadeOutMsOverride': fadeOutMsOverride,
      'crossfadeMsOverride': crossfadeMsOverride,
      'order': order,
    };
  }

  factory SoundPad.fromJson(Map<String, dynamic> json) {
    return SoundPad(
      id: json['id'] as String,
      folderId: json['folderId'] as String,
      label: json['label'] as String,
      colorValue: (json['colorValue'] as num).toInt(),
      icon: PadIcon.values.byName(json['icon'] as String),
      audioPath: json['audioPath'] as String,
      isAsset: json['isAsset'] as bool? ?? false,
      type: PadType.values.byName(json['type'] as String),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      retriggerMode: json['retriggerMode'] != null
          ? RetriggerMode.values.byName(json['retriggerMode'] as String)
          : RetriggerMode.restart,
      fadeInMsOverride: (json['fadeInMsOverride'] as num?)?.toInt(),
      fadeOutMsOverride: (json['fadeOutMsOverride'] as num?)?.toInt(),
      crossfadeMsOverride: (json['crossfadeMsOverride'] as num?)?.toInt(),
      order: (json['order'] as num).toInt(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SoundPad &&
            other.id == id &&
            other.folderId == folderId &&
            other.label == label &&
            other.colorValue == colorValue &&
            other.icon == icon &&
            other.audioPath == audioPath &&
            other.isAsset == isAsset &&
            other.type == type &&
            other.volume == volume &&
            other.retriggerMode == retriggerMode &&
            other.fadeInMsOverride == fadeInMsOverride &&
            other.fadeOutMsOverride == fadeOutMsOverride &&
            other.crossfadeMsOverride == crossfadeMsOverride &&
            other.order == order;
  }

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    label,
    colorValue,
    icon,
    audioPath,
    isAsset,
    type,
    volume,
    retriggerMode,
    fadeInMsOverride,
    fadeOutMsOverride,
    crossfadeMsOverride,
    order,
  );

  @override
  String toString() =>
      'SoundPad(id: $id, folderId: $folderId, label: $label, type: $type)';
}

/// Global audio, appearance, and session defaults for the soundboard.
class BoardSettings {
  const BoardSettings({
    this.defaultFadeInMs = 500,
    this.defaultFadeOutMs = 1000,
    this.defaultCrossfadeMs = 2000,
    this.masterVolume = 1.0,
    this.keepScreenAwake = false,
    this.gridDensity = GridDensity.standard,
    this.themeMode = AppThemeMode.dark,
    this.seedColorValue = 0xFFD4882A,
    this.useDynamicColor = true,
  });

  final int defaultFadeInMs;
  final int defaultFadeOutMs;
  final int defaultCrossfadeMs;
  final double masterVolume;
  final bool keepScreenAwake;
  final GridDensity gridDensity;
  final AppThemeMode themeMode;
  final int seedColorValue;
  final bool useDynamicColor;

  BoardSettings copyWith({
    int? defaultFadeInMs,
    int? defaultFadeOutMs,
    int? defaultCrossfadeMs,
    double? masterVolume,
    bool? keepScreenAwake,
    GridDensity? gridDensity,
    AppThemeMode? themeMode,
    int? seedColorValue,
    bool? useDynamicColor,
  }) {
    return BoardSettings(
      defaultFadeInMs: defaultFadeInMs ?? this.defaultFadeInMs,
      defaultFadeOutMs: defaultFadeOutMs ?? this.defaultFadeOutMs,
      defaultCrossfadeMs: defaultCrossfadeMs ?? this.defaultCrossfadeMs,
      masterVolume: masterVolume ?? this.masterVolume,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      gridDensity: gridDensity ?? this.gridDensity,
      themeMode: themeMode ?? this.themeMode,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'defaultFadeInMs': defaultFadeInMs,
      'defaultFadeOutMs': defaultFadeOutMs,
      'defaultCrossfadeMs': defaultCrossfadeMs,
      'masterVolume': masterVolume,
      'keepScreenAwake': keepScreenAwake,
      'gridDensity': gridDensity.name,
      'themeMode': themeMode.name,
      'seedColorValue': seedColorValue,
      'useDynamicColor': useDynamicColor,
    };
  }

  factory BoardSettings.fromJson(Map<String, dynamic> json) {
    return BoardSettings(
      defaultFadeInMs: (json['defaultFadeInMs'] as num?)?.toInt() ?? 500,
      defaultFadeOutMs: (json['defaultFadeOutMs'] as num?)?.toInt() ?? 1000,
      defaultCrossfadeMs: (json['defaultCrossfadeMs'] as num?)?.toInt() ?? 2000,
      masterVolume: (json['masterVolume'] as num?)?.toDouble() ?? 1.0,
      keepScreenAwake: json['keepScreenAwake'] as bool? ?? false,
      gridDensity: json['gridDensity'] != null
          ? GridDensity.values.byName(json['gridDensity'] as String)
          : GridDensity.standard,
      themeMode: json['themeMode'] != null
          ? AppThemeMode.values.byName(json['themeMode'] as String)
          : AppThemeMode.dark,
      seedColorValue: (json['seedColorValue'] as num?)?.toInt() ?? 0xFFD4882A,
      useDynamicColor: json['useDynamicColor'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BoardSettings &&
            other.defaultFadeInMs == defaultFadeInMs &&
            other.defaultFadeOutMs == defaultFadeOutMs &&
            other.defaultCrossfadeMs == defaultCrossfadeMs &&
            other.masterVolume == masterVolume &&
            other.keepScreenAwake == keepScreenAwake &&
            other.gridDensity == gridDensity &&
            other.themeMode == themeMode &&
            other.seedColorValue == seedColorValue &&
            other.useDynamicColor == useDynamicColor;
  }

  @override
  int get hashCode => Object.hash(
    defaultFadeInMs,
    defaultFadeOutMs,
    defaultCrossfadeMs,
    masterVolume,
    keepScreenAwake,
    gridDensity,
    themeMode,
    seedColorValue,
    useDynamicColor,
  );

  @override
  String toString() =>
      'BoardSettings(fadeIn: $defaultFadeInMs, fadeOut: $defaultFadeOutMs, '
      'crossfade: $defaultCrossfadeMs, masterVolume: $masterVolume)';
}

/// Complete persisted snapshot of folders, pads, and user settings.
class SoundLibrary {
  const SoundLibrary({
    this.schemaVersion = 1,
    required this.folders,
    required this.pads,
    this.settings = const BoardSettings(),
  });

  final int schemaVersion;
  final List<SoundFolder> folders;
  final List<SoundPad> pads;
  final BoardSettings settings;

  SoundLibrary copyWith({
    int? schemaVersion,
    List<SoundFolder>? folders,
    List<SoundPad>? pads,
    BoardSettings? settings,
  }) {
    return SoundLibrary(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      folders: folders ?? this.folders,
      pads: pads ?? this.pads,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'folders': folders.map((folder) => folder.toJson()).toList(),
      'pads': pads.map((pad) => pad.toJson()).toList(),
      'settings': settings.toJson(),
    };
  }

  factory SoundLibrary.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'] as List<dynamic>? ?? const <dynamic>[];
    final rawPads = json['pads'] as List<dynamic>? ?? const <dynamic>[];
    final rawSettings = json['settings'] as Map<String, dynamic>?;
    return SoundLibrary(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      folders: List<SoundFolder>.unmodifiable(
        rawFolders.map(
          (item) => SoundFolder.fromJson(item as Map<String, dynamic>),
        ),
      ),
      pads: List<SoundPad>.unmodifiable(
        rawPads.map((item) => SoundPad.fromJson(item as Map<String, dynamic>)),
      ),
      settings: rawSettings != null
          ? BoardSettings.fromJson(rawSettings)
          : const BoardSettings(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SoundLibrary &&
            other.schemaVersion == schemaVersion &&
            _listEquals(other.folders, folders) &&
            _listEquals(other.pads, pads) &&
            other.settings == settings;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    Object.hashAll(folders),
    Object.hashAll(pads),
    settings,
  );

  @override
  String toString() =>
      'SoundLibrary(schemaVersion: $schemaVersion, folders: ${folders.length}, '
      'pads: ${pads.length})';
}

/// Snapshot of a single pad's active playback voice or error state.
class ActiveVoiceState {
  const ActiveVoiceState({
    required this.padId,
    this.handle,
    required this.phase,
    this.currentVolume = 1.0,
    this.activeLayerCount = 1,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.startedAt,
    this.errorMessage,
  });

  final String padId;
  final String? handle;
  final PadPlaybackPhase phase;
  final double currentVolume;
  final int activeLayerCount;
  final Duration position;
  final Duration duration;
  final DateTime? startedAt;
  final String? errorMessage;

  /// Effective per-pad playback volume in the range `[0.0, 1.0]`.
  double get volume => currentVolume;

  ActiveVoiceState copyWith({
    String? padId,
    String? handle,
    bool clearHandle = false,
    PadPlaybackPhase? phase,
    double? currentVolume,
    int? activeLayerCount,
    Duration? position,
    Duration? duration,
    DateTime? startedAt,
    bool clearStartedAt = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ActiveVoiceState(
      padId: padId ?? this.padId,
      handle: clearHandle ? null : (handle ?? this.handle),
      phase: phase ?? this.phase,
      currentVolume: currentVolume ?? this.currentVolume,
      activeLayerCount: activeLayerCount ?? this.activeLayerCount,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'padId': padId,
      'handle': handle,
      'phase': phase.name,
      'currentVolume': currentVolume,
      'activeLayerCount': activeLayerCount,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'startedAt': startedAt?.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory ActiveVoiceState.fromJson(Map<String, dynamic> json) {
    final startedAtRaw = json['startedAt'] as String?;
    return ActiveVoiceState(
      padId: json['padId'] as String,
      handle: json['handle'] as String?,
      phase: PadPlaybackPhase.values.byName(json['phase'] as String),
      currentVolume: (json['currentVolume'] as num?)?.toDouble() ?? 1.0,
      activeLayerCount: (json['activeLayerCount'] as num?)?.toInt() ?? 1,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      startedAt: startedAtRaw != null ? DateTime.parse(startedAtRaw) : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ActiveVoiceState &&
            other.padId == padId &&
            other.handle == handle &&
            other.phase == phase &&
            other.currentVolume == currentVolume &&
            other.activeLayerCount == activeLayerCount &&
            other.position == position &&
            other.duration == duration &&
            other.startedAt == startedAt &&
            other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    padId,
    handle,
    phase,
    currentVolume,
    activeLayerCount,
    position,
    duration,
    startedAt,
    errorMessage,
  );

  @override
  String toString() =>
      'ActiveVoiceState(padId: $padId, handle: $handle, phase: $phase, '
      'layers: $activeLayerCount)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
