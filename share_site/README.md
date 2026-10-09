# Share-link site

ChessHive's "Share position" button makes links like
`https://eduardsleonovics.github.io/chesshive/p/?fen=...`. Android opens
these links straight in the app once it has verified that the site trusts
the app. Without the app installed, the link shows this page instead: a
picture of the position, an "Open in ChessHive" button, and a Google Play
link.

This folder is the content for the GitHub user site `EduardsLeonovics.github.io`.
Android only reads `assetlinks.json` from the domain root, so the files
must go in that repo, not in `chess_scanner`.

## One-time setup

1. **Release key.** Create one and keep it safe, because the Play Store
   requires the same key for every update:
   ```
   keytool -genkey -v -keystore %USERPROFILE%\keys\chesshive-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Then create `app/android/key.properties` (git ignores it):
   ```
   storeFile=C:/Users/Eduards/keys/chesshive-upload-keystore.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
2. **Fingerprint.** Get the key's SHA-256 and put it in
   `.well-known/assetlinks.json`, in place of `REPLACE_WITH_RELEASE_KEY_SHA256`:
   ```
   keytool -list -v -keystore %USERPROFILE%\keys\chesshive-upload-keystore.jks -alias upload
   ```
   Once the app is on Google Play with Play App Signing, also add the
   *app signing* key's SHA-256 from Play Console › Setup › App signing.
   Add it as a second entry in the same list.
3. **Publish.** On GitHub, create the public repo `EduardsLeonovics.github.io`.
   Copy this folder's contents into it, including `.well-known/` and
   `.nojekyll` (without `.nojekyll`, GitHub Pages hides `.well-known`), then
   push. Under Settings › Pages, publish from the `main` branch root.
4. **Check.** Open
   `https://eduardsleonovics.github.io/.well-known/assetlinks.json`, then
   install a release build (`flutter build apk --release`) and run:
   ```
   adb shell pm get-app-links com.eduards.chess_scanner
   ```
   The domain should show as `verified`.

Until then, links still work through the page's "Open in ChessHive" button,
which uses the `chesshive://` scheme.
