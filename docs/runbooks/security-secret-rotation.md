# Runbook: Rotating Compromised Secrets

## 1. Secrets Compromised in Git History
The following values were committed to Git and must be treated as permanently compromised:
- `WEBHOOK_SECRET`: `dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400`
- `APP_AUTH_TOKEN`: `bt_sec_99a81f3d4c72e01b88e2`
- Default Supabase Anon Key in `supabase_config.dart`

## 2. Generating New Secrets
Run the following in a secure terminal:
```bash
python -c "import secrets; print('WEBHOOK_SECRET=' + secrets.token_hex(32))"
python -c "import secrets; print('APP_AUTH_TOKEN=bt_sec_' + secrets.token_hex(16))"
```

## 3. Server Deployment Update
1. Update `.env` on your deployment host (e.g. VPS / Cloud Run / Coolify):
   ```bash
   WEBHOOK_SECRET=<new-generated-hex-64>
   APP_AUTH_TOKEN=<new-generated-bt-sec-token>
   SUPABASE_JWT_SECRET=<supabase-project-jwt-secret>
   REDIS_URL=redis://redis:6379/0
   ENV=production
   ```
2. Restart the AI service container:
   ```bash
   docker compose down && docker compose up -d --build
   ```

## 4. Mobile Client Build Update
When building the Flutter APK/iOS bundle, supply the new values strictly via `--dart-define`:
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your-anon-key> \
  --dart-define=FASTAPI_BASE_URL=https://<your-api-domain> \
  --dart-define=APP_AUTH_TOKEN=<new-generated-bt-sec-token> \
  --dart-define=WEBHOOK_SECRET=<new-generated-hex-64>
```

## 5. Git History Cleansing (Optional/Recommended for Public Repos)
If this repository is or will become public, run `git filter-repo` or BFG Repo-Cleaner to scrub the historical commit blobs containing the compromised strings.
