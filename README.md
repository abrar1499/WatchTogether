# Operation Dust Signal (Godot)

A third-person tactical shooter for Android, rebuilt in **Godot 4.3**. So far: the soldier, the rifles and a practice yard with enemy soldiers. The Hadra base mission, grenades and the rest of the earlier browser version come back in later phases.

## What is in phase 1

- Mixamo "Swat Guy" with walk, run, strafe, walk/run backwards, crouch walk, kneel, aim and jump clips, driven by an AnimationTree: one direction clip at a time with a short crossfade, and the aim or reload pose on the arms and chest while the legs keep walking.
- Each gun's pistol grip sits inside the closed right hand (index finger on the trigger), the barrel lined up with the crosshair; IK puts the left palm under the rifle's handguard, fingers wrapped round it, or over the right hand on the pistol (off while reloading or switching).
- Crouch-running plays the crouch walk faster (the crouch-run clip carried the body 1.8 m behind itself).
- SD-9 pistol, M4A1 and AK-47 with their own sounds, recoil, muzzle flash, tracers and bullet holes.
- Over-the-shoulder camera with a close and a closer view, a zoomed aim, and first person with the soldier's own arms and gun in view (iron sights on the AK and pistol, through the red dot on the M4).
- While aiming or firing the chest turns so the rifle stays on the crosshair whichever way the legs are running.
- Enemy soldiers in the yard (six per wave, desert uniforms, AK-47s): they stand guard or walk a short beat, see the player in front of them (slower to notice a crouched player, quicker up close), hear unsuppressed gunfire, call the soldiers near them, then aim and fire bursts, close in or hunt the last place they saw the player. Headshots kill at once; they die with Mixamo death clips. A new wave comes when the yard is clear.
- Player health with a hit flash and a mark toward the shooter; health comes back after a few quiet seconds; when killed the player is back at the start a moment later.
- Practice yard: the reserve ammunition refills, so the rifles never end up at 0 / 0.
- Phone controls: move with the bottom-left thumb, drag anywhere else to look, FIRE (slide the same finger to aim while firing), AIM, CROUCH, JUMP, RELOAD, SWAP, VIEW, MENU. On a computer: WASD, mouse, left/right click, Shift, C, Space, R, Q or 1/2/3, V, Esc.

## Project

- `godot/`: the Godot project (`project.godot`, `main.tscn`, `scripts/`, `assets/`)
  - `scripts/main.gd`: the yard, lighting, effects, sounds and the update check
  - `scripts/player.gd`: movement, animation, guns, IK, camera, shooting, health; also builds the other soldiers (first-person arms, enemies) with the same grip
  - `scripts/enemy.gd`: the enemy soldier
  - `scripts/touch.gd`: on-screen controls, keyboard/mouse, HUD, start and pause menus
  - `assets/soldier.glb`: the soldier with its Mixamo animations
  - `assets/guns/`: the AK-47, M4A1 (with red-dot sight) and suppressed SD-9 pistol, `assets/sfx/`: the sound files (unedited)
- `tools/gunbuild/`: the Python script that builds the three gun models (real size, rounded edges, wood-grain and metal textures); run `python3 build_guns.py ../../godot/assets/guns` (needs numpy, Pillow, mapbox_earcut)
- `android/debug.keystore`: the signing key of the original app, so the game installs as its update
- `.github/workflows/build.yml`: exports the APK with Godot and publishes it

## Android app and updates

Every push exports an APK with GitHub Actions and publishes it under **Releases** as `v<number>` (file `DustSignal.apk`). The app id is `com.abrar.watchtogether` and the APK is signed with the same key as before, so it installs over the earlier app. Godot test builds are published as pre-releases. The game checks the releases when it starts and offers **Update** on the start screen (it opens the APK download).

To open the project on a computer, install Godot 4.3 and open `godot/project.godot`.

## Credits

Soldier character and animations from [Mixamo](https://www.mixamo.com) (Adobe).

Sounds in `godot/assets/sfx/` are unedited sound effects from [Pixabay](https://pixabay.com/sound-effects/), used under the Pixabay Content License:
- AK-47: "AK-47 sound effect" by sovetsky_rastov72
- M4A1: "Gun fire" by foisal72 (475286)
- Pistol: "Gun rifle shots" by dennish18
- Pistol reload: "1911 reload" by freesound_community
- M4 and AK-47 reload: "Gun full reload" by melbeebelbee
- Footsteps: "Footsteps in wet coarse sand" (freesound_community), "Running on the floor" (thumblegray)
- Enemy rifles: "Machin gun AK47 sound effect 6" (beetpro)
- Deaths: "Male death scream horror", "Dramatic death collapse" and "Character fall impact" (universfield), "Male death sound" (vinodadora); the player's last breath is the player's own recording
