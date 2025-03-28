# Fully Managed Concert System

Based on the article: https://solarhorizon.dev/2024/07/30/top-to-bottom-fully-managed-rojo/

Currently Lune is having cookie issues, so we won't be using that or Asphalt, but the structure is there if we need it.

## Project Structure

```
src/
├── client/           # Client-side code
│   ├── BeatEffects.luau
│   ├── LightingEffects.luau
│   └── init.client.luau
├── server/           # Server-side code
│   ├── MusicController.luau
│   └── init.server.luau
└── shared/          # Shared code and types
    ├── AudioScapeAPI.luau
    └── Types.luau
```

## Build System

- **Rojo**: Used for syncing files to Roblox Studio
- **Lune**: Will be used for asset management (currently disabled due to cookie issues)
- **Asphalt**: Will be used for asset bundling (currently disabled)

### Asset Management
- Asphalt applies to:
  - `assets/init.luau`
  - Images in `assets/`
  - `.toml` configuration files

- Lune applies to:
  - Models in `assets/`
  - Map and lighting folders (not currently in repo)

## Key Components

1. **AudioScapeAPI**: Interface to the AudioScape API for music timing data
2. **MusicController**: Server-side music playback and synchronization
3. **BeatEffects**: Client-side beat-based visual effects
4. **LightingEffects**: Client-side lighting and atmosphere effects

## Type System

The project uses Luau's strict type checking. All type definitions are centralized in `src/shared/Types.luau`.
