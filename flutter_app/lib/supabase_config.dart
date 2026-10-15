/// Supabase + FastAPI configuration.
/// All values MUST be provided via --dart-define at build time.
/// Example: flutter build apk --dart-define=SUPABASE_URL=https://...
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Deprecated: use [supabasePublishableKey] instead.
const supabaseAnonKey = supabasePublishableKey;

const fastapiBaseUrl = String.fromEnvironment('FASTAPI_BASE_URL');

const fastapiWebhookUrl = String.fromEnvironment('FASTAPI_WEBHOOK_URL');

const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');

const webhookSecret = String.fromEnvironment('WEBHOOK_SECRET');
