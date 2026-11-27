import 'package:auraboard/domain/models.dart';

/// Creates the bundled first-run demo library with offline WAV assets.
SoundLibrary createDemoLibrary() {
  const combatFolder = SoundFolder(
    id: 'folder_combat',
    name: 'Combat',
    order: 0,
  );
  const tavernFolder = SoundFolder(
    id: 'folder_tavern',
    name: 'Tavern',
    order: 1,
  );
  const dungeonFolder = SoundFolder(
    id: 'folder_dungeon',
    name: 'Dungeon',
    order: 2,
  );

  const pads = <SoundPad>[
    SoundPad(
      id: 'pad_sword_clash',
      folderId: 'folder_combat',
      label: 'Sword Clash',
      colorValue: 0xFFB84A39,
      icon: PadIcon.sword,
      audioPath: 'assets/demo_audio/sword_clash.wav',
      isAsset: true,
      type: PadType.effect,
      order: 0,
    ),
    SoundPad(
      id: 'pad_fireball',
      folderId: 'folder_combat',
      label: 'Fireball',
      colorValue: 0xFFD96B27,
      icon: PadIcon.fire,
      audioPath: 'assets/demo_audio/fireball_boom.wav',
      isAsset: true,
      type: PadType.effect,
      order: 1,
    ),
    SoundPad(
      id: 'pad_battle_drums',
      folderId: 'folder_combat',
      label: 'Battle Drums',
      colorValue: 0xFF9C3D3D,
      icon: PadIcon.drum,
      audioPath: 'assets/demo_audio/combat_drums_music.wav',
      isAsset: true,
      type: PadType.music,
      order: 2,
    ),
    SoundPad(
      id: 'pad_tavern_hearth',
      folderId: 'folder_tavern',
      label: 'Tavern Hearth',
      colorValue: 0xFFC68A32,
      icon: PadIcon.tavern,
      audioPath: 'assets/demo_audio/tavern_hearth_music.wav',
      isAsset: true,
      type: PadType.music,
      order: 0,
    ),
    SoundPad(
      id: 'pad_heroic_chime',
      folderId: 'folder_tavern',
      label: 'Heroic Chime',
      colorValue: 0xFFD4A738,
      icon: PadIcon.bell,
      audioPath: 'assets/demo_audio/heroic_chime.wav',
      isAsset: true,
      type: PadType.effect,
      order: 1,
    ),
    SoundPad(
      id: 'pad_steady_rain',
      folderId: 'folder_tavern',
      label: 'Steady Rain',
      colorValue: 0xFF3E6D8C,
      icon: PadIcon.rain,
      audioPath: 'assets/demo_audio/rain_ambience.wav',
      isAsset: true,
      type: PadType.ambience,
      order: 2,
    ),
    SoundPad(
      id: 'pad_dungeon_wind',
      folderId: 'folder_dungeon',
      label: 'Dungeon Wind',
      colorValue: 0xFF4F5D75,
      icon: PadIcon.wind,
      audioPath: 'assets/demo_audio/dungeon_wind_ambience.wav',
      isAsset: true,
      type: PadType.ambience,
      order: 0,
    ),
  ];

  return const SoundLibrary(
    schemaVersion: 1,
    folders: <SoundFolder>[combatFolder, tavernFolder, dungeonFolder],
    pads: pads,
    settings: BoardSettings(),
  );
}
