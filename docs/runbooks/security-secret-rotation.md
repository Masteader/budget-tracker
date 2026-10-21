# Runbook: Rotating Compromised Secrets

## 1. Secrets Compromised in Git History
The following values were committed to Git and must be treated as permanently compromised:
- `WEBHOOK_SECRET`: `<redacted: rotated>`
- `APP_AUTH_TOKEN`: `<redacted: rotated>`
- Default Supabase Anon Key in `supabase_config.dart`

## 2. Generating New Secrets
Run the following in a secure terminal:
```bash
python -c "import secrets; print('WEBHOOK_SECRET=' + secrets.token_hex(32))"
python -c "import secrets; print('APP_AUTH_TOKEN=bt_sec_' + secrets.token_hex(16))"
```

## 3. Server Deployment Update
1. Update the environment of the deployment host (Railway today; or a VPS / container host with `ai_service/.env`):
   ```bash
   WEBHOOK_SECRET=<new-generated-hex-64>
   APP_AUTH_TOKEN=<new-generated-bt-sec-token>   # legacy firewall pass for old app builds only
   ENV=production                                # unset also counts as production
   # optional:
   # SUPABASE_JWT_SECRET=<legacy-hs256-jwt-secret>  # only if the project still issues HS256 user tokens
   # REDIS_URL=redis://<your-redis-host>:6379/0     # docker-compose.yml starts no Redis service
   ```
2. Redeploy / restart the service (with Docker Compose: `cd ai_service && docker compose down && docker compose up -d --build`).
3. Rotating the Supabase secret key or the Google/Gemini key follows the same pattern; step-by-step
   owner procedures are in [`../review/OWNER_ACTIONS.md`](../review/OWNER_ACTIONS.md).

## 4. Mobile Client Build Update
When building the Flutter APK/iOS bundle, supply the values strictly via `--dart-define`.
The app authenticates with the user's Supabase JWT; it does not read `APP_AUTH_TOKEN`, and
`WEBHOOK_SECRET` is optional (omit it and requests are sent unsigned; the app starts either way):
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-anon-key> \
  --dart-define=FASTAPI_BASE_URL=https://<your-api-domain>
# optional request signing (must equal the server's current WEBHOOK_SECRET):
#   --dart-define=WEBHOOK_SECRET=<new-generated-hex-64>
```
After rotating `WEBHOOK_SECRET` on the server, builds that still sign with the old value keep
working: their signature no longer verifies, but the request is authenticated by the user's JWT, so
the backend logs a rate-limited warning ("Ignoring X-Signature header ...") and serves it. Those
warnings show how many old builds are still in use; new builds can drop the define.

## 5. Git History Cleansing (Optional/Recommended for Public Repos)
If this repository is or will become public, run `git filter-repo` or BFG Repo-Cleaner to scrub the historical commit blobs containing the compromised strings.
