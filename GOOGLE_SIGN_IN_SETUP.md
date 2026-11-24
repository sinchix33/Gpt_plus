# Google Sign-In setup

The app now uses Google's official `GoogleSignIn` Swift Package (10.x). Google authentication cannot work until the app owner supplies a real iOS OAuth client ID.

## Required one-time configuration

1. In Google Cloud Console, create an OAuth client of type **iOS**.
2. Set its bundle identifier to `com.sinchix33.gptplus`.
3. Copy the client ID into `GIDClientID` in `.github/ios-overrides/ChatGPT-iOS/Resources/Info.plist`.
4. Replace `com.googleusercontent.apps.REPLACE_WITH_CLIENT_ID` with the exact `REVERSED_CLIENT_ID` value supplied by Google.
5. Rebuild and test on a physical iPhone.

The Google SDK handles the system authentication session and restores the prior Google sign-in. The app does not collect Google passwords or read browser cookies.

## ChatGPT sign-in limitation

“Continue with ChatGPT” opens the official `https://chatgpt.com/auth/login` page in an in-app Safari browser. This is a website session only. ChatGPT does not provide a public consumer OAuth flow that allows a third-party app to receive the user's ChatGPT website session. The app does not extract cookies, reuse private mobile credentials, or claim that browser sign-in authenticates the native app.

A Google identity is also separate from an OpenAI/ChatGPT identity. A production app backend would need to verify Google ID tokens if it needs its own server-side user accounts.
