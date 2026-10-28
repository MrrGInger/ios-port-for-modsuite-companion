# Experimental VRChat website sign-in

Settings > Open VRChat sign-in opens a WebView at https://vrchat.com/home/login.
After signing in, tap Connect website session. Android's WebView CookieManager reads
VRChat-domain cookies **on device**; Dart verifies them directly against
https://api.vrchat.cloud/api/1/auth/user and stores valid credentials in
flutter_secure_storage. The native bridge does not read Google or ModSuite cookies.

**Not a verified OAuth integration.** Google or other identity providers may
block embedded WebViews. VRChat may set cookies on different domains or use
cookies that are not valid for the API. In these cases the app displays an
error; manual VRChat auth cookie entry remains available. No browser cookie
is ever sent to ModSuite. Do not use live moderation until the independent
ban/unban authorization and incident logging workflow is verified.

Build on Windows in modsuite_mobile:
C:\\src\\flutter\\bin\\flutter.bat pub get
C:\\src\\flutter\\bin\\flutter.bat run
