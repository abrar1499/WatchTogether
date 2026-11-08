# Operation Dust Signal

A first-person stealth shooter that runs in the browser. Mission 1: get into the Hadra relay base, copy the codes from the bunker terminal, and reach landing zone Raven.

## Play

Open `index.html` through any web server (for example GitHub Pages). It does not work when opened straight from the file system, because the soldier model is loaded with `fetch`.

**Computer:** WASD move, mouse look, click fire, Shift sprint, C crouch, 1/2 weapons, R reload, B binoculars, M map, E use, Space jump, Esc pause.

**Phone:** hold the phone sideways. Left thumb moves, right thumb looks, and the on-screen buttons do the rest.

## Android app

Every push builds an APK with GitHub Actions and publishes it under **Releases** as `Dust Signal v<number>` (file `DustSignal.apk`). It installs as its own app (`com.abrar.dustsignal`), next to WatchTogether, and is not marked as the latest release, so the WatchTogether updater ignores it. Install a newer APK over the old one to update.

The app shows the same `index.html` full screen in landscape. It needs internet the first time, to load three.js from the CDN.

## Your own soldier

On the start screen, tap **Upload soldier file** and choose a Mixamo character downloaded as **FBX Binary, T-pose**. The game converts it in the browser, shrinks the textures, and saves it on that device. **Use standard soldier** switches back.

## Files

- `index.html`: the whole game (three.js r128 from cdnjs)
- `models/soldier.b64.txt`: the standard soldier with its animations, as a base64 GLB
- `app/`: the Android wrapper (a full-screen WebView)
- `.github/workflows/build.yml`: builds and releases the APK

## Credits

Soldier character and animations from [Mixamo](https://www.mixamo.com) (Adobe).
