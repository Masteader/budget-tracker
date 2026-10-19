-- =============================================================================
-- Local Supabase platform stubs for plain PostgreSQL (16+) test databases.
--
-- Supabase-managed objects (auth schema, storage schema, client roles,
-- extensions schema, realtime publication, default grants) do not exist in a
-- vanilla Postgres cluster. This bootstrap recreates the minimal, behaviourally
-- faithful subset that supabase/schema.sql, supabase/migrations/*.sql and
-- supabase/tests/*.sql depend on, so the full schema can be rebuilt and tested
-- locally without Docker or the hosted project.
--
-- This file is applied by `supabase/tests/run_tests.py --rebuild` BEFORE
-- schema.sql. It is idempotent and is skipped by the test-file glob (it is not a
-- test). Never apply it to a real Supabase project: the platform already owns
-- these objects there.
-- =============================================================================

\set ON_ERROR_STOP on

-- ── Client roles (same names and RLS posture as Supabase) ───────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOLOGIN NOINHERIT;
    END IF;
END $$;

GRANT anon, authenticated, service_role TO authenticator;

-- ── Schemas ─────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;

GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Supabase installs extensions into the `extensions` schema and puts it on the
-- database search_path.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = "$user", public, extensions', current_database());
END $$;
SET search_path = "$user", public, extensions;

-- ── auth schema ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth.users (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at         timestamptz NOT NULL DEFAULT now()
);

-- Same definitions as Supabase GoTrue's auth helpers (claims come from the
-- PostgREST GUC `request.jwt.claims`; the legacy per-claim GUC is honoured too).
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(
        coalesce(
            current_setting('request.jwt.claim.sub', true),
            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        ),
        ''
    )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(
        coalesce(
            current_setting('request.jwt.claim.role', true),
            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        ),
        ''
    )::text;
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(
        coalesce(
            current_setting('request.jwt.claim.email', true),
            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
        ),
        ''
    )::text;
$$;

CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb;
$$;

GRANT EXECUTE ON FUNCTION auth.uid(), auth.role(), auth.email(), auth.jwt()
    TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO service_role;

-- ── storage schema ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS storage.buckets (
    id                 text PRIMARY KEY,
    name               text NOT NULL,
    owner              uuid,
    public             boolean DEFAULT false,
    file_size_limit    bigint,
    allowed_mime_types text[],
    created_at         timestamptz DEFAULT now(),
    updated_at         timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bucket_id  text REFERENCES storage.buckets(id),
    name       text,
    owner      uuid,
    metadata   jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

-- Same bodies as supabase/storage-api's SQL helpers.
CREATE OR REPLACE FUNCTION storage.foldername(name text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[1:array_length(_parts, 1) - 1];
END
$$;

CREATE OR REPLACE FUNCTION storage.filename(name text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;

CREATE OR REPLACE FUNCTION storage.extension(name text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;

GRANT ALL ON storage.objects, storage.buckets TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION storage.foldername(text), storage.filename(text), storage.extension(text)
    TO anon, authenticated, service_role;

-- ── Realtime publication ────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- ── Supabase default privileges on the public schema ────────────────────────
-- Supabase grants table/sequence/function privileges in `public` to the API
-- roles by default and relies on RLS (plus explicit REVOKEs) for isolation.
-- Reproducing this is essential: a table without RLS is world-readable there.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
