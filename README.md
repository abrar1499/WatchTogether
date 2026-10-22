# Watch Together (v0.1)

Door bethay log ek hi waqt par YouTube video dekhein. Ek banda room banata hai, code share karta hai, baaki join karte hain. Koi bhi play, pause ya aage/peeche kare to sab ke phone par wahi ho jata hai. Saath mein chat bhi hai.

## Is version mein kya hai
- Naam ke saath room banana (6 harf ka code) ya code se join karna
- YouTube link paste karke sab ke liye video chalana (watch, youtu.be, shorts, live links)
- Play / pause / seek realtime sync (Firebase server time se drift theek hota hai)
- **Sync** button: agar kisi ka video peeche reh jaye to ek tap mein barabar
- Kitne log room mein hain, aur room chat
- Invite button se code WhatsApp waghera par share

## Ek dafa setup: Firebase (free)
1. https://console.firebase.google.com par jaa kar **Add project** karein (naam: WatchTogether). Analytics off kar sakte hain.
2. Left menu: **Build → Realtime Database → Create database**. Location chunein, phir **Start in locked mode**.
3. **Rules** tab mein is repo ki `database.rules.json` ka content paste karke **Publish** karein.
4. **Project settings (gear icon) → General → Your apps → Android icon**. Package name: `com.abrar.watchtogether`. Register karein (google-services.json download karne ki zaroorat nahi, skip kar dein).
5. Wahi page par yeh values milengi. GitHub repo mein **Settings → Secrets and variables → Actions → New repository secret** se yeh 4 secrets banayein:

| Secret ka naam | Kahan se milega |
|---|---|
| `FIREBASE_API_KEY` | Project settings → Web API Key |
| `FIREBASE_APP_ID` | Your apps → Android app → App ID (`1:...:android:...`) |
| `FIREBASE_PROJECT_ID` | Project settings → Project ID |
| `FIREBASE_DB_URL` | Realtime Database page ke upar wala URL (`https://...firebasedatabase.app`) |

6. **Actions** tab → **Build APK** → **Run workflow**. Build ke baad artifact se APK download karke install karein.

Har build ka version number barhta hai aur signing key repo mein fixed hai, is liye naya APK purane ke upar update ho jayega, uninstall ki zaroorat nahi.

## Apne computer par build (optional)
`local.properties` mein yeh 4 lines daal dein, phir Android Studio se Run karein:
```
FIREBASE_API_KEY=...
FIREBASE_APP_ID=...
FIREBASE_PROJECT_ID=...
FIREBASE_DB_URL=...
```

## Pata hona chahiye
- Kuch YouTube videos (zyada tar music labels ki) embed allow nahi karti; un par error aayega.
- Abhi rules sab ke liye open hain (jis ke paas room code ho woh join kar sakta hai). Public release se pehle Firebase Anonymous Auth lagana behtar hoga.
- Netflix is version mein nahi hai: har banda apne account se dekhe aur app sirf sync kare, yeh agla step hai.

## Agle steps
- Voice call (WebRTC)
- Fullscreen mode, emoji reactions
- Facebook / TikTok links
- Netflix sync (har user ka apna login)
