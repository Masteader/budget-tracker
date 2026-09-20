/// Supabase + FastAPI configuration.
/// Default values are configured for local development and direct running.
library;

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qnhyiszgiymsypcwnntu.supabase.co',
);

const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFuaHlpc3pnaXltc3lwY3dubnR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5MjM2NjYsImV4cCI6MjEwNTQ5OTY2Nn0.bOazpdgpRKOB2n60ZgGL3Vgjd4oPp5yxZ0VqpeyLz_U',
);

const fastapiWebhookUrl = String.fromEnvironment(
  'FASTAPI_WEBHOOK_URL',
  defaultValue: 'http://192.168.0.143:8000/webhook/sms',
);

const webhookSecret = String.fromEnvironment(
  'WEBHOOK_SECRET',
  defaultValue:
      'dc48149f54288779f92f8da4963ef08c2ba58e15a62dc78eea2b6e98c7d0c400',
);
