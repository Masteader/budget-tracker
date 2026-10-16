/// Supabase + FastAPI configuration.
/// Default values connect to the live Supabase project and production backend.
/// Overrides can be provided via --dart-define at build time.
library;

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qnhyiszgiymsypcwnntu.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_MKtHOBzNx__wuWOMTGo3eA_2T8KD0lY',
  ),
);

/// Deprecated: alias for [supabasePublishableKey].
const supabaseAnonKey = supabasePublishableKey;

const fastapiBaseUrl = String.fromEnvironment(
  'FASTAPI_BASE_URL',
  defaultValue: 'https://budget.fmsco.com.sa',
);

const fastapiWebhookUrl = String.fromEnvironment(
  'FASTAPI_WEBHOOK_URL',
  defaultValue: 'https://budget.fmsco.com.sa',
);

const authRedirectUrl = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: 'https://budget.fmsco.com.sa',
);

const webhookSecret = String.fromEnvironment(
  'WEBHOOK_SECRET',
  defaultValue: '239e6a9141efe77bd8193faba777496f2e5bf1c072edf65a20b07082b00b4cc7',
);
