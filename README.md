# Operation Dust Signal

A first-person stealth shooter that runs in the browser. Mission 1: get into the Hadra relay base, copy the codes from the bunker terminal, and reach landing zone Raven.

## Play

Open `index.html` through any web server (for example GitHub Pages). It does not work when opened straight from the file system, because the soldier model is loaded with `fetch`.

The game works **offline**: three.js, its loaders and meshoptimizer are bundled in `vendor/` (the Android app ships them in its assets), so no internet connection is needed to start or play. Only the Google web fonts need a connection; without one, system fonts are used. An uploaded soldier or song is stored on the device, so it also plays offline.

**Computer:** WASD move, mouse look, click fire, Shift sprint, C crouch, 1/2/3 pistol, M4A1, AK-47, R reload, B binoculars, M map, V first/third person, E use, Space jump, Esc pause.

**Phone:** hold the phone sideways. Drag in the bottom-left corner to move: a small push sneaks, half a push walks, the edge sprints. Drag anywhere else on the screen to aim. Only the FIRE button shoots; keep the finger down and slide it to aim while firing, lift it to stop. VIEW switches between third person (your soldier on screen, the default) and first person.

## Android app

Every push builds an APK with GitHub Actions and publishes it under **Releases** as `v<number>` (file `DustSignal.apk`), marked as the latest release.

The app uses the same app id (`com.abrar.watchtogether`) and signing key as the old WatchTogether app, so it installs as an update over it. The app checks for newer releases when it starts, downloads them in the background, and asks **Update now / Later** before installing.

It shows the same `index.html` full screen in landscape, and needs internet the first time to load three.js from the CDN.

## Graphics

The start screen has **Low** and **High**. Phones start on Low: no real-time shadows, simpler lighting, no clouds, render scale 1x, fewer shrubs and lighter soldiers. High turns those on. Both modes merge the static scenery and each gun into a few meshes to keep draw calls down.

## Your own soldier

On the start screen, tap **Upload soldier file** and choose a Mixamo character downloaded as **FBX Binary, T-pose**. The game converts it in the browser, shrinks the textures, and saves it on that device. **Use standard soldier** switches back.

## Music

**Upload music** picks a song from the device instead. It is saved on that device only and plays on a loop during the mission. **Remove music** turns it off.

## Files

- `index.html`: the whole game (three.js r128 from cdnjs)
- `sfx/`: the gun sounds, unedited original files
- `models/soldier.b64.txt`: the standard soldier (Mixamo "Swat Guy", merged into 2 meshes and simplified to about 16k triangles) with its animations, as a base64 GLB
- `vendor/`: bundled libraries (three.js r128 and r160 modules, meshoptimizer), MIT licensed, with their licenses
- `app/`: the Android wrapper (a full-screen WebView)
- `.github/workflows/build.yml`: builds and releases the APK

## Credits

Soldier character and animations from [Mixamo](https://www.mixamo.com) (Adobe).

Sounds in `sfx/` are unedited sound effects from [Pixabay](https://pixabay.com/sound-effects/), used under the Pixabay Content License:
- AK-47: "AK-47 sound effect" by sovetsky_rastov72
- M4A1: "Gun fire" by foisal72 (475286)
- Pistol: "Gun rifle shots" by dennish18
- Enemy rifles: "Machin gun AK47 sound effect 6" by beetpro
- Pistol reload: "1911 reload" by freesound_community
- M4 and AK-47 reload: "Gun full reload" by melbeebelbee

The game plays only these files (no synthesized sounds). Automatic weapons loop the steady full-auto part of their file while FIRE is held.
