# City assets (mission 2)

The buildings, street textures and props of mission 2 come from [Poly Haven](https://polyhaven.com) (CC0) and are
cut down for phones here. `godot/scripts/city.gd` assembles the city from the results.

Needs Python 3 with numpy, Pillow and `meshoptimizer` (`pip install meshoptimizer`), and Godot 4.3.

1. Download (1k textures): `python3 phget.py model modular_urban_apartments_facade 1k ../../godot/assets/city/facade`
   (only its plaster textures are used now), `python3 phget.py model <prop> 1k ../../godot/assets/city/props/<prop>`
   for rollershutter_door, exterior_aircon_unit, covered_car, planter_box_01, concrete_road_barrier, and
   `python3 phget.py tex <id> 1k ...` for asphalt_02, worn_asphalt, square_concrete_pavers, concrete_pavement,
   gravel_concrete, concrete_wall_006 (into `assets/city/tex`).
2. Buildings: no models. `city.gd` makes their pieces (a wall bay with a window's hole, the window, a doorway,
   plinth, string course, parapet, corner posts) from a few rectangles each. They used to be the facade kit's
   scanned pieces, simplified by `kit_lod.py`: forty times the vertices, and most of a mission's loading time.
3. Props: `python3 prop_lod.py <prop>/<prop>.gltf <ratio>` writes `<prop>_game.gltf` with its own compact `.bin`
   (ratios used: barrier 0.012, air conditioner 0.02 and then 0.2 of that, covered car 0.15, planter 0.05,
   shutter 0.2); `python3 gltf_prune.py exterior_aircon_unit_game.gltf exterior_aircon_unit_rusted` drops the
   rusted variant.
4. The plaster colour is a greyed copy of the kit's texture (`plaster_grey_diff.jpg` in `assets/city/tex`) so each
   building can be tinted.

`build_city.py` builds the simple vehicles still used (burnt car, burnt bus, militia pickup):
`python3 build_city.py ../../godot/assets/city` (uses `tools/gunbuild/meshlib.py`).

## Mission 3

- Props: `python3 phget.py model <id> 1k <dir>/<id>` then `python3 prop_pack.py <dir>/<id> ../../godot/assets/city/props/<id> <triangles> 512`:
  every node of the model baked into one mesh per material, simplified with meshoptimizer, colour and normal textures at
  512 px (`<id>_game.gltf`, its `.bin`, `textures/`). The ids are listed in the main README's credits.
- Textures: `python3 phget.py tex <id> 1k <dir>`; the colour map goes in at 1k and the normal map at 512 px as
  `godot/assets/city/tex3/<id>_diff.jpg` and `<id>_nor.jpg`. `pale_paint` and `white_ceiling` are recoloured copies of
  `peeling_painted_wall` and `ceiling_interior`.
- Vehicles: `build_city.py` also writes `police.glb`, `ambulance.glb`, `van_burnt.glb`, `truck_mil.glb`, `apc.glb` and
  `forklift.glb`.
- In the `.import` file of every texture: `compress/mode=2`, `mipmaps/generate=true`, and `compress/normal_map=1` for
  normal maps (compressed on the phone's graphics chip, a third of the memory).
- Soldiers seen from far off: `python3 skin_lod.py ../../godot/assets/chars/<name>.glb 0.3` writes `<name>_low.glb`, the same skeleton and skin with about
  a third of the triangles and no pictures; the game draws it beyond 12 m with the full model's materials.
