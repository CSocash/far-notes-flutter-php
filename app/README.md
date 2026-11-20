# FAR Notes app (Flutter)

The iOS and Android app for the FAR Notes study log. It talks to the PHP server in `../backend` with a
bearer token (it signs in with `X-Far-Notes-Client: app`), and never uses the website's cookie.

- `lib/core.dart`: pure tracker logic ported from `app-core.js` (unit tests in `test/core_test.dart`).
- `lib/api.dart`: the server API and the saved session token.
- `lib/save_queue.dart`: autosave with a 350 ms delay and one queue per item, like the website.
- `lib/screens/`: sign in, create account, forgot password and the tracker.

Accessibility labels match the website's ("Mark 91.103(a) as covered", "Study items in ..."), so the
Appium tests in `../tests/device` find the same names the Playwright tests use.

## Run it

Start the server first (`sh backend/start.sh` from the repo root), then from this folder:

```
flutter run
```

Without a setting, the iOS Simulator calls `http://127.0.0.1:3000` and the Android emulator
`http://10.0.2.2:3000`. Point it somewhere else with
`flutter run --dart-define=FAR_NOTES_API_URL=http://127.0.0.1:3100`.

`flutter test` runs the unit tests and `flutter analyze` checks the code.
