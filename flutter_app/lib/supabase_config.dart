/// Supabase + FastAPI configuration.
/// Default values are configured for local development and direct running.
library;

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qnhyiszgiymsypcwnntu.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_MKtHOBzNx__wuWOMTGo3eA_2T8KD0lY',
);

/// Deprecated: use [supabasePublishableKey] instead.
const supabaseAnonKey = supabasePublishableKey;

const fastapiBaseUrl = String.fromEnvironment(
  'FASTAPI_BASE_URL',
  defaultValue: 'https://budget.fmsco.com.sa',
);

const fastapiWebhookUrl = String.fromEnvironment(
  'FASTAPI_WEBHOOK_URL',
  defaultValue: 'https://budget.fmsco.com.sa/webhook/sms',
);


const webhookSecret = String.fromEnvironment(
  'WEBHOOK_SECRET',
  defaultValue:
      'dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400',
);
