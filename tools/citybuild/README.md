# City assets (mission 2)

The buildings, street textures and props of mission 2 come from [Poly Haven](https://polyhaven.com) (CC0) and are
cut down for phones here. `godot/scripts/city.gd` assembles the city from the results.

Needs Python 3 with numpy, Pillow and `meshoptimizer` (`pip install meshoptimizer`), and Godot 4.3.

1. Download (1k textures): `python3 phget.py model modular_urban_apartments_facade 1k ../../godot/assets/city/facade`,
   `python3 phget.py model <prop> 1k ../../godot/assets/city/props/<prop>` for rollershutter_door, exterior_aircon_unit,
   covered_car, planter_box_01, concrete_road_barrier, and `python3 phget.py tex <id> 1k ...` for asphalt_02,
   worn_asphalt, square_concrete_pavers, concrete_pavement, gravel_concrete, concrete_wall_006 (into `assets/city/tex`).
2. Facade kit: `python3 kit_lod.py ../../godot/assets/city/facade/modular_urban_apartments_facade.gltf`, import the
   project (`godot --headless --path ../../godot --import`), then
   `godot --headless --path ../../godot -s tools/kitbake.gd`: every piece is saved, with only the vertices it still
   uses, as `assets/city/kit/<piece>.res` (near) and `<piece>_lo.res` (far). The downloaded kit itself is not kept in
   the repository, only these pieces and the textures `city.gd` uses.
3. Props: `python3 prop_lod.py <prop>/<prop>.gltf <ratio>` writes `<prop>_game.gltf` with its own compact `.bin`
   (ratios used: barrier 0.012, air conditioner 0.02, covered car 0.15, planter 0.05, shutter 0.2);
   `python3 gltf_prune.py exterior_aircon_unit_game.gltf exterior_aircon_unit_rusted` drops the rusted variant.
4. The plaster and trim colours are greyed copies of the kit's textures (`plaster_grey_diff.jpg`,
   `trim_01_grey_diff.jpg`, `trim_02_grey_diff.jpg` in `assets/city/tex`) so each building can be tinted.

`build_city.py` builds the simple vehicles still used (burnt car, burnt bus, militia pickup):
`python3 build_city.py ../../godot/assets/city` (uses `tools/gunbuild/meshlib.py`).
