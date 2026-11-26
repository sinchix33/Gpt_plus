# Authentication setup

## Google Sign-In

The app uses Google's official `GoogleSignIn` Swift Package (10.x). Google authentication cannot work until the app owner supplies a real iOS OAuth client ID.

1. In Google Cloud Console, create an OAuth client of type **iOS**.
2. Set its bundle identifier to `com.sinchix33.gptplus`.
3. Copy the client ID into `GIDClientID` in `.github/ios-overrides/ChatGPT-iOS/Resources/Info.plist`.
4. Replace `com.googleusercontent.apps.REPLACE_WITH_CLIENT_ID` with the exact `REVERSED_CLIENT_ID` value supplied by Google.
5. Rebuild and test on a physical iPhone.

Do not commit OAuth client secrets, API keys, provisioning profiles, signing certificates, or private keys. The public iOS OAuth client ID is not a client secret.

## Sign in with ChatGPT

The app now contains a native Swift implementation of OpenAI's documented open-source Sign in with ChatGPT flow:

- First sign-in uses `dynamic_agent_client`, `agent_name_hint=GPT Plus`, and a persistent per-installation `ext_agent_host_id`.
- It starts an HTTP loopback callback on `127.0.0.1` with the documented `/auth/callback` path.
- It uses fresh state, nonce, and PKCE S256 values for each attempt.
- It saves the issued `oaiapp_...` client ID, verifies the ID-token ES256 signature against OpenAI's JWKS, and checks issuer, audience, expiry, nonce, and subject.
- Access and refresh tokens are stored in the iOS Keychain. Refresh-token rotation is saved, and sign-out attempts revocation using OpenID discovery metadata.
- ChatGPT plan usage is marked authorized only when the returned token scope includes `chatgpt.tokens.use.direct`.

The browser callback and token exchange must be tested on a physical iPhone. In particular, confirm that the Safari authentication view can reach the app's loopback listener on the chosen iOS version. A successful identity login is separate from permission to use a ChatGPT plan.

### Important limitation

This change connects and securely stores the ChatGPT identity and optional plan-usage authorization. It does **not yet migrate the app's existing chat/network layer to the official Responses API using the SIWC access token**. Do not assume existing app chat requests are using the ChatGPT plan token until that separate integration is implemented and tested.

OpenAI's official documentation:
- [Open-source registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts, sessions, refresh, and revocation](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Token reference](https://developers.openai.com/siwc/token-sharing-open-source/token-reference)

This repository is public. Review the complete Git history and rotate any credential that may have been committed before publication.
