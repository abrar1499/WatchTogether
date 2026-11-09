# Operation Dust Signal (Godot)

A third-person tactical shooter for Android, rebuilt in **Godot 4.3**. This is phase 1: the soldier, the rifles and a small practice yard. Guards, the Hadra base mission, effects and menus from the earlier browser version come back in later phases.

## What is in phase 1

- Mixamo "Swat Guy" with walk, run, strafe, walk/run backwards, crouch walk, kneel, aim and jump clips, driven by an AnimationTree: one direction clip at a time with a short crossfade, and the aim or reload pose on the arms and chest while the legs keep walking.
- Each gun's pistol grip sits inside the closed right hand (index finger on the trigger), the barrel lined up with the crosshair; IK puts the left palm under the rifle's handguard, fingers wrapped round it, or over the right hand on the pistol (off while reloading or switching).
- Crouch-running plays the crouch walk faster (the crouch-run clip carried the body 1.8 m behind itself).
- SD-9 pistol, M4A1 and AK-47 with their own sounds, recoil, muzzle flash, tracers and bullet holes.
- Over-the-shoulder camera with a close and a closer view, a zoomed aim, and first person with the gun in view.
- Practice yard: the reserve ammunition refills, so the rifles never end up at 0 / 0.
- Phone controls: move with the bottom-left thumb, drag anywhere else to look, FIRE (slide the same finger to aim while firing), AIM, CROUCH, JUMP, RELOAD, SWAP, VIEW, MENU. On a computer: WASD, mouse, left/right click, Shift, C, Space, R, Q or 1/2/3, V, Esc.

## Project

- `godot/`: the Godot project (`project.godot`, `main.tscn`, `scripts/`, `assets/`)
  - `scripts/main.gd`: the yard, lighting, effects, sounds and the update check
  - `scripts/player.gd`: movement, animation, guns, IK, camera, shooting
  - `scripts/touch.gd`: on-screen controls, keyboard/mouse, HUD, start and pause menus
  - `assets/soldier.glb`: the soldier with its Mixamo animations
  - `assets/guns/`: the three rifles, `assets/sfx/`: the sound files (unedited)
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
