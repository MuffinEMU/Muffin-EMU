# vancouver.rpx

A 3D flyover of Metro Vancouver, BC for Wii U homebrew.

Rendering: software-rasterised voxel-space terrain (Comanche style) into a 160x90 buffer,
drawn through OSScreen at 4x. No GX2 shaders. Terrain is a 128x96 heightmap (12 KB,
`source/vancouver_height.h`) hand-shaped from a sketch grid by `tools/gen_vancouver_height.py`;
no SRTM or other dataset is used. It has the North Shore mountains (snow-capped above a
height threshold), flat Richmond and Delta, the Fraser River, Burnaby Mountain, Stanley Park
in green, water with an animated tint, distance fog and a sun term. Towers (downtown and
Metrotown) are generated extruded boxes with lit windows at night; Lions Gate and Port Mann
are simple flat deck spans.

Controls (GamePad): left stick moves, right stick turns and looks up/down, L up, ZL down,
A day/night, B reset. The GamePad shows a top-down mini-map with your position, heading
and labels for Vancouver, Burnaby, Richmond, Surrey, North Vancouver, West Vancouver,
Coquitlam, New Westminster, Delta and Stanley Park. Close the app to exit.

Map data (c) OpenStreetMap contributors, ODbL. The outline is hand-sketched with real
geography as reference; no OSM data files are included. Made by MuffinEMU.
