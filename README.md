# Operation Dust Signal (Godot)

A third-person tactical shooter for Android, rebuilt in **Godot 4.3**: missions (30 planned, opening one after another) and a training yard with every gun.

## Missions

- MISSIONS on the start screen lists all thirty: the first is open, each one completed opens the next (progress kept on the phone). They are all inside the game itself, nothing extra to download; missions not built yet show "coming soon". Each starts with a briefing and its objectives; the objectives stay on screen with a marker (and distance) on the next one. Killed: mission failed, try again. In a mission you carry what the briefing says, ammunition runs out, and you take guns and magazines from the guards you kill.
- Mission 1, BROKEN RELAY: a fenced militia radio station in the desert. A gate with a guard booth and barrier, a watchtower with a sniper (Dragunov), a barracks with a guard on its roof, a command hut with a plank door, a lattice radio mast and the diesel generator that powers it; patrols inside the wire, a torn stretch of fence on the east side. Take the relay codes from the command hut, knock out the generator, get out through the north gate to the pickup point (green smoke). A guard who has seen you raises the alarm a few seconds later unless he is dead by then: a siren, and four more soldiers come up the road from the north.

## Training yard and everything in it

- The practice yard: rippled sand with gentle dunes beyond the yard and hazy rocky mountains on the horizon, corrugated shipping containers (one stack two high), wooden crates, concrete T-wall barriers, a sandbag wall laid bag by bag, ribbed fuel drums, a plastered building with door, barred windows, air conditioner and roof tank, boulders, steel targets and a barbed-wire fence. Neutral daylight: white sun, blue sky, a soft fill light, so everything keeps its real colour.
- Mixamo "Swat Guy" with walk, run, strafe, walk/run backwards, crouch walk, kneel, aim and jump clips, driven by an AnimationTree: one direction clip at a time with a short crossfade, and the aim or reload pose on the arms and chest while the legs keep walking.
- Each gun's pistol grip sits inside the closed right hand (index finger on the trigger), the barrel lined up with the crosshair; IK puts the left palm under the rifle's handguard, fingers wrapped round it, or over the right hand on the pistol (off while reloading or switching).
- Crouch-running plays the crouch walk faster (the crouch-run clip carried the body 1.8 m behind itself).
- SD-9 pistol, M4A1 and AK-47 with their own sounds, recoil and bullet holes. Muzzle flash: a white-hot star seen from the front and the flame leaving the muzzle seen from the side, a warm flash of light and a wisp of smoke (only a small spark from the suppressed pistol). Tracers: short orange streaks that fly down the bullet's path, ours and the enemy's.
- Over-the-shoulder camera with a close and a closer view, a zoomed aim, and first person with the soldier's own arms and gun in view (iron sights on the AK and pistol, through the red dot on the M4).
- While aiming or firing the chest turns so the rifle stays on the crosshair whichever way the legs are running.
- Enemy soldiers in the yard (six per wave, two each of three characters: a gas-masked SWAT officer, an olive-drab soldier and a blue-uniformed soldier, all with AK-47s; the player's own clips and grip are fitted to each): they stand guard or walk a short beat and see the player in front of them (slower to notice a crouched player, quicker up close). Only a soldier who has seen the player fights; gunfire or a blast within earshot, or a call from a soldier close by, sends the others to look round where it came from, rifle up, and back to their post if they find nothing. Once in a fight they aim and fire bursts, close in or hunt the last place they saw the player. Headshots kill at once; they die with Mixamo death clips. A new wave comes when the yard is clear.
- Music from the earlier version, soft and mixed by what is happening: a whoosh and the opening of a trailer when the game starts; while the yard is quiet a low suspense bed, a night sound and now and then a raven; a short stinger when a soldier spots the player; in a firefight one action piece at a time, faded in and out with a rest between pieces; a heartbeat at low health; everything fades when the player is killed.
- Rounds go through wooden crates, container walls and drums (with less force each time) and stop in concrete, sandbags, rock and the building. A round only hits a soldier where it meets his body (head, chest, arms, legs, as capsules round the bones), not the space round him; arms and legs take less damage, the head kills. Crates splinter and, after about eight rounds, come apart into their sides and lid flying as boards (a crate stacked on top drops to the ground). A fuel drum holed a few times leaks fuel that catches fire, burns for a few seconds and blows up (at once if it takes enough rounds): fireball, smoke column, flash of light, the torn and blackened drum thrown up still burning, its lid spinning off, a scorch mark; the blast hurts soldiers and the player nearby in the open and sets off drums next to it. Everything is back for the next wave.
- In a fight the soldiers keep moving: a burst or two from one spot, then off to another (low cover they can fire over if there is some, working round to one side), ducking between bursts and popping up to fire, and moving at once when hit. Their accuracy and damage are as before.
- Six guns: SD-9 pistol, M4A1, AK-47, Dragunov SVD (one heavy round, PSO-1 scope: aiming looks through it with its chevron reticle and range scale, in any camera view), a 12-gauge pump-action shotgun (nine pellets; the pump slides back and forward after every shot with the left hand on it) and an RPG-7 (the rocket flies with a smoke trail and blows up on whatever it hits, with a back-blast behind the tube; the rocket shows in the tube while loaded; aiming looks through the PGO-7 sight).
- Powerful hits: a soldier killed from close up (or by the shotgun or the SVD further off) is thrown back a little way off his feet; an explosion throws him further. A heavy hit that does not kill staggers him. Each death clip falls one way (forward, to the side, or back); the one used is the one that falls along the shot with the least turn of the body, and only where there is room (not into a crate or a wall, not off the roof).
- Grenades (four, two more each wave): the soldier swings his arm and throws; the grenade bounces and goes off 2.4 s later. Soldiers run from a grenade that lands near them, and some of them throw one at the place where they last saw the player hiding (a warning shows which way it is). Hit markers at the crosshair (red for a kill).
- HOLSTER slings the rifle on the back (the pistol goes into a thigh holster): the arms hang free and he runs a little faster; HOLSTER again or FIRE draws it.
- Climbing: JUMP next to a crate, drum, the sandbag wall or a container climbs up onto it; at a concrete T-wall he goes up and over (the button reads CLIMB when there is something to climb). Concrete stairs with a railing go up the side of the building to its roof, which has a parapet to take cover behind; one enemy keeps watch from the roof.
- Sound: gunfire and explosions with a little open-air reverb and late echoes off the hills, far-off shots duller; rounds striking steel, wood, sand, concrete or a body each sound different; enemy rounds that pass close crack by; burning drums roar and crackle; spent cases fly out of the guns (red shells from the shotgun's pump). These effect sounds are made in the game from noise and tones.
- Wounds: rounds hit where they meet the body. A leg hit makes a soldier limp (he cannot run, he bleeds); both legs, or one heavy round, put him down: he fights on lying on the ground and crawls. An arm hit spoils his aim. The player hit in a leg cannot sprint for a while; in an arm, aims less steadily.
- Wooden doors: rounds go through and leave holes on both faces, enough of them and the door comes apart into its planks; ACTION (KICK) next to a closed door bursts it open (and breaks a shot-up one).
- ACTION next to a dead soldier (TAKE AK, TAKE SVD...): the player kneels, rolls the body onto its side and takes the gun out of his hand: a new gun, or two more magazines for one already carried.
- Every round leaves a mark: a spurt of dust and grit and a small dimple in sand, sparks off steel, chips and grey dust off concrete and rock, splinters off wood, sand out of sandbags; bullet holes stay.
- Player health with a hit flash and a mark toward the shooter; health comes back after a few quiet seconds; when killed the player is back at the start a moment later.
- Practice yard: the reserve ammunition refills, so the rifles never end up at 0 / 0.
- Phone controls: move with the bottom-left thumb, drag anywhere else to look, FIRE (slide the same finger to aim while firing), AIM, CROUCH, JUMP / CLIMB, RELOAD, SWAP, GRENADE, HOLSTER, ACTION (shows what it will do: KICK, TAKE AK, TAKE CODES...), VIEW, MENU. On a computer: WASD, mouse, left/right click, Shift, C, Space, R, Q or 1-6, G, H, E, V, Esc.

## Project

- `godot/`: the Godot project (`project.godot`, `main.tscn`, `scripts/`, `assets/`)
  - `scripts/main.gd`: the yard, lighting, effects, sounds and the update check
  - `scripts/player.gd`: movement, animation, guns, IK, camera, shooting, health; also builds the other soldiers (first-person arms, enemies) with the same grip
  - `scripts/enemy.gd`: the enemy soldier
  - `scripts/touch.gd`: on-screen controls, keyboard/mouse, HUD, start, mission list, briefing, result and pause menus
  - `scripts/missions.gd`: the missions (level, soldiers, objectives, alarm, pickup point) and the progress
  - `assets/soldier.glb`: the soldier with its Mixamo animations
  - `assets/guns/`: the AK-47, M4A1 (with red-dot sight), suppressed SD-9 pistol, Dragunov SVD (PSO-1 scope), pump shotgun (sliding pump) and RPG-7 (removable rocket), `assets/sfx/`: the sound files (unedited)
- `tools/envbuild/`: the script that builds the yard's props and textures in `godot/assets/env/` (shipping containers, wooden crates, concrete T-walls, fuel drums, sandbags, the building and its outside stairs; sand, rock and concrete textures); `ONLY=building,stairs` rebuilds just those
- `tools/charbuild/`: how the enemy characters in `godot/assets/chars/` were made from the original Mixamo FBX files
- `tools/fxbuild/`: the script that draws the muzzle-flash and tracer textures in `godot/assets/fx/`
- `tools/gunbuild/`: the Python script that builds the six gun models (real size, rounded edges, wood-grain and metal textures); run `python3 build_guns.py ../../godot/assets/guns` (needs numpy, Pillow, mapbox_earcut)
- `android/debug.keystore`: the signing key of the original app, so the game installs as its update
- `.github/workflows/build.yml`: exports the APK with Godot and publishes it

## Android app and updates

Every push exports an APK with GitHub Actions and publishes it under **Releases** as `v<number>` (file `DustSignal.apk`). The app id is `com.abrar.watchtogether` and the APK is signed with the same key as before, so it installs over the earlier app. Godot test builds are published as pre-releases. The game checks the releases when it starts and offers **Update** on the start screen (it opens the APK download).

To open the project on a computer, install Godot 4.3 and open `godot/project.godot`.

## Credits

Soldier character, the three enemy characters and the animations from [Mixamo](https://www.mixamo.com) (Adobe).

Sounds in `godot/assets/sfx/` are unedited sound effects from [Pixabay](https://pixabay.com/sound-effects/), used under the Pixabay Content License:
- AK-47: "AK-47 sound effect" by sovetsky_rastov72
- M4A1: "Gun fire" by foisal72 (475286)
- Pistol: "Gun rifle shots" by dennish18
- Pistol reload: "1911 reload" by freesound_community
- M4 and AK-47 reload: "Gun full reload" by melbeebelbee
- Footsteps: "Footsteps in wet coarse sand" (freesound_community), "Running on the floor" (thumblegray)
- Enemy rifles: "Machin gun AK47 sound effect 6" (beetpro)
- Music and atmosphere (`godot/assets/music/`): "Cinematic action epic trailer: Iron Vanguard" (openmindaudio), "Descent whoosh" (viralaudio), "Tense suspense ambience" (absolutesound), "Mid nights sound" (ncprime), "Raven call" (freesound_community), "Scary sound effect" and "Heartbeat sound" (dragon-studio), "Action loop E 90 BPM" (brvhrtz), "Action trailer" (arctsound)
- Deaths: "Male death scream horror", "Dramatic death collapse" and "Character fall impact" (universfield), "Male death sound" (vinodadora); the player's last breath is the player's own recording
- The soldiers' grunts when hit are the player's own ElevenLabs recording; the RPG launch and the explosions are the player's own recordings
- The SVD, shotgun and RPG fire the single shots from the AK-47 recording played lower and louder; the shotgun's pump is the rifle reload sound
