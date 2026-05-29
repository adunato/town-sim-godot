# Tilesheet Tilemap POC

This proof of concept demonstrates a safe, file-driven path from atlas metadata to a Godot `TileMapLayer`.

Input:

- `res://data/poc/tilesheet_tilemap_poc.json`

Generated outputs:

- `res://assets/poc/terrain_tilesheet_poc.png`
- `res://scenes/poc/tilesheet_tileset_poc.tres`
- `res://scenes/poc/tilesheet_tilemap_poc.tscn`

Regenerate with:

```powershell
& "C:\Users\danie\projects\TownSim\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . -s "res://scripts/tools/generate_tilesheet_tilemap_poc.gd"
```

The JSON schema mirrors the terrain data needed from Unity-style atlas extraction: atlas path, fixed tile size, per-tile atlas rectangles, and placed cell coordinates. It also supports `rect_origin: "bottom_left"` so Unity texture-space rectangles can be converted into Godot atlas coordinates.

Current scope:

- Supports fixed-size, grid-aligned terrain tiles.
- Generates a placeholder tilesheet so no third-party art is committed.
- Populates one `TileMapLayer` from JSON cells.
- Does not convert Unity custom tile scripts, rule tiles, animation, materials, or collision.
