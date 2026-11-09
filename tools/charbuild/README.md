# Enemy characters

`convert.gd` turns the three Mixamo characters from the `models` release (`character.zip`: `Ch35_nonPBR.fbx`,
`Ch49_nonPBR.fbx`, `Swat.fbx`, about 260 MB) into the small GLBs in `godot/assets/chars/` (about 6.6 MB together):
about half the triangles (Godot's own simplifier, skin weights kept), 1024 px JPEG textures, eyelash cards dropped,
bones renamed `mixamorig_X` -> `mixamorigX` to match the soldier, no animations (the game copies the soldier's
clips onto them).

To run it: make an empty Godot 4.3 project, put the three FBX files in `src/`, copy `convert.gd` in, import
(`godot --headless --path . --import`), then `godot --headless --path . --script res://convert.gd`. The GLBs
are written to `out/` (`gasmask.glb`, `olive.glb`, `blue.glb`).
