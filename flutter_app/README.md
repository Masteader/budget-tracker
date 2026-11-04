# Budget Tracker — Flutter App

Android / iOS client. It talks to Supabase directly (publishable key, Row Level Security, Realtime)
and to the FastAPI service (`ai_service/`) with the user's Supabase JWT.

## Run

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<id>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-or-anon-key> \
  --dart-define=FASTAPI_BASE_URL=http://<your-machine-ip>:8000
```

All flags (required and optional) are documented in the root
[`README.md`](../README.md#flutter-app---dart-define-flags) and defined in
[`lib/supabase_config.dart`](lib/supabase_config.dart). There are no built-in defaults: a missing
required flag stops the app at startup, and service-role / `sb_secret_` keys are rejected.

## Test

```bash
flutter test      # unit and widget tests in test/
flutter analyze   # must report "No issues found!"
```

## Release

`flutter build apk --release` with the same `--dart-define` values (`https://` URLs). Signing reads
`android/key.properties` (git-ignored: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`);
without it the release build falls back to the debug key with a warning.

## Layout

`lib/l10n` (ar / en / ur strings, `context.tr`), `models`, `providers`, `screens`, `services`
(API clients, Supabase, offline SQLite queue), `theme`, `widgets`. Project rules:
[`../.agents/rules/`](../.agents/rules/).
