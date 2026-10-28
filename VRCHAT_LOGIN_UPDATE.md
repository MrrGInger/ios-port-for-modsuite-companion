# VRChat browser sign-in update

Added an **Open VRChat sign-in** button that opens the official VRChat login in the external Android browser, where the user can select Google or other sign-in providers offered by VRChat. The app does not request or store Google passwords or Google tokens.

**Important:** Signing in to VRChat in the browser does **not** automatically authenticate the Companion VRChat API client. No supported browser-to-API session handoff has been verified. The existing manual VRChat auth-cookie entry remains available and is needed for API features until a supported flow is implemented. The button must not be represented as completing Companion login.

ModSuite pairing and server code are unchanged. VRChat cookies are handled only by VrchatApi and are not sent to ModSuite.

Build from the modsuite_mobile folder:

```powershell
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat run
```
