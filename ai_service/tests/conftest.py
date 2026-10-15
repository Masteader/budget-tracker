"""Shared test fixtures and environment setup."""
import os

# Set test secrets before any imports of main
os.environ.setdefault("WEBHOOK_SECRET", "test_secret_for_ci_only_do_not_use_in_prod")
os.environ.setdefault("APP_AUTH_TOKEN", "test_token_for_ci_only")
os.environ.setdefault("ENV", "development")
os.environ.setdefault("SUPABASE_URL", "https://mockproject.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "mock_service_role_key_for_testing")
