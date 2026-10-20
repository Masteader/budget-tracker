#!/usr/bin/env python3
"""Database test runner for a local Docker Postgres or a plain local Postgres (run by hand before each release; the project has no CI).

Default behaviour (unchanged): run every ``NN_*.sql`` test file through
``docker exec -i budget_tracker_review_pg psql`` against ``$DB_NAME``
(default ``live_rebuilt_round5``).

Plain-psql mode (no Docker needed)::

    # Rebuild a throwaway database from scratch and run all tests against it
    PGHOST=localhost PGPORT=54329 PGUSER=postgres \\
        python3 supabase/tests/run_tests.py --psql --rebuild --db bt_audit_tests

``--psql`` (or ``BT_DB_TEST_MODE=psql``) talks to the server with the local
``psql`` binary using the standard libpq environment variables (PGHOST,
PGPORT, PGUSER, PGPASSWORD). ``--rebuild`` drops and recreates the database,
then applies ``00_local_supabase_stubs.sql`` (platform stubs), ``schema.sql``,
``seed.sql`` (system categories that migrations reference) and every migration in replay order (see ``migration_replay_order``) before
running the tests. Never point ``--rebuild`` at a real Supabase project.

Without ``--rebuild`` the tests run against the existing database named by
``--db``. Pre-flight against a local replica of live (never live itself)::

    # Expected live baseline: the chain as it stood before PREFIX
    python3 supabase/tests/run_tests.py --psql --rebuild --stop-before 20261020005000 \\
        --no-tests --db bt_repo_baseline
    # Apply the pending migrations (filename >= PREFIX) to an existing local
    # replica, then run the suite against it
    python3 supabase/tests/run_tests.py --psql --apply-from 20261020005000 --db bt_live_replica
"""

import argparse
import glob
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
SUPABASE_DIR = os.path.dirname(TEST_DIR)
STUBS_FILE = os.path.join(TEST_DIR, "00_local_supabase_stubs.sql")
DOCKER_CONTAINER = "budget_tracker_review_pg"

# Files whose shipped version prefix sorts before a migration they depend on.
# `20261018_membership_sync_and_shared_account_policies.sql` creates a policy on
# `public.accounts`, which is created by
# `20261018_multi_source_income_and_accounts.sql` (same version prefix, later
# alphabetically). Replay must apply the dependency first.
REPLAY_DEPENDENCIES = {
    "20261018_membership_sync_and_shared_account_policies.sql": [
        "20261018_multi_source_income_and_accounts.sql",
    ],
}


def migration_replay_order(migration_dir):
    """Return migration paths sorted by filename, honouring REPLAY_DEPENDENCIES."""
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(migration_dir, "*.sql")))
    ordered = []
    placed = set()

    def place(name):
        if name in placed:
            return
        for dep in REPLAY_DEPENDENCIES.get(name, []):
            if dep in names:
                place(dep)
        placed.add(name)
        ordered.append(name)

    for name in names:
        place(name)
    return [os.path.join(migration_dir, n) for n in ordered]


def psql_command(db_name, use_psql, user="postgres"):
    if use_psql:
        return ["psql", "-X", "-q", "-d", db_name, "-v", "ON_ERROR_STOP=1"]
    return [
        "docker", "exec", "-i", DOCKER_CONTAINER,
        "psql", "-U", user, "-d", db_name, "-v", "ON_ERROR_STOP=1",
    ]


def run_sql_file(file_path, db_name="live_rebuilt_round5", use_psql=False, quiet=False):
    if not quiet:
        print(f"\n--- Running: {os.path.basename(file_path)} ---")

    with open(file_path, "rb") as f:
        sql_content = f.read()

    proc = subprocess.run(psql_command(db_name, use_psql), input=sql_content, capture_output=True)
    stdout = proc.stdout.decode("utf-8", errors="replace")
    stderr = proc.stderr.decode("utf-8", errors="replace")

    if proc.returncode != 0:
        print(f"FAILED: {os.path.basename(file_path)} (exit code {proc.returncode}):")
        if stderr:
            print(stderr)
        if stdout:
            print(stdout)
        return False

    if not quiet:
        print("PASSED")
        combined = stdout + "\n" + stderr
        for line in combined.splitlines():
            if "NOTICE:" in line or "DETAIL:" in line:
                print(f"  {line}")
    return True


def rebuild_database(db_name, stop_before=None):
    """Drop/recreate db_name and replay stubs + schema + migrations (psql mode only).

    ``stop_before``: replay only migrations whose filename sorts before this
    prefix (e.g. ``20261020`` rebuilds the chain as it was before that day).
    """
    if not re.fullmatch(r"[A-Za-z0-9_]+", db_name):
        raise SystemExit(f"Refusing to rebuild database with unsafe name: {db_name!r}")

    for cmd in (["dropdb", "--if-exists", db_name], ["createdb", db_name]):
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(f"{' '.join(cmd)} failed: {proc.stderr.strip()}")

    steps = [
        STUBS_FILE,
        os.path.join(SUPABASE_DIR, "schema.sql"),
        os.path.join(SUPABASE_DIR, "seed.sql"),
    ]
    migrations = migration_replay_order(os.path.join(SUPABASE_DIR, "migrations"))
    if stop_before:
        migrations = [m for m in migrations if os.path.basename(m) < stop_before]
    steps += migrations
    print(f"Rebuilding {db_name}: {len(steps)} files (stubs, schema.sql, seed.sql, migrations)")
    for step in steps:
        if not run_sql_file(step, db_name=db_name, use_psql=True, quiet=True):
            raise SystemExit(f"Rebuild failed while applying {os.path.relpath(step, SUPABASE_DIR)}")
    print("Rebuild complete.")


def apply_pending_migrations(db_name, apply_from, use_psql):
    """Apply migrations whose filename sorts at or after ``apply_from`` to an existing database."""
    migrations = [m for m in migration_replay_order(os.path.join(SUPABASE_DIR, "migrations"))
                  if os.path.basename(m) >= apply_from]
    print(f"Applying {len(migrations)} pending migration(s) to {db_name}")
    for m in migrations:
        print(f"  {os.path.basename(m)}")
        if not run_sql_file(m, db_name=db_name, use_psql=use_psql, quiet=True):
            raise SystemExit(f"Migration failed: {os.path.basename(m)}")
    print("Pending migrations applied.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--psql", action="store_true",
                        help="Use the local psql binary (libpq env vars) instead of docker exec.")
    parser.add_argument("--rebuild", action="store_true",
                        help="Drop, recreate and replay the full schema before testing (implies --psql).")
    parser.add_argument("--stop-before", default=None, metavar="PREFIX",
                        help="With --rebuild: replay only migrations whose filename sorts before PREFIX.")
    parser.add_argument("--no-tests", action="store_true",
                        help="Only rebuild / apply; do not run the test files.")
    parser.add_argument("--apply-from", default=None, metavar="PREFIX",
                        help="Without --rebuild: apply migrations whose filename sorts at or after PREFIX to the "
                             "existing --db first (local replicas only).")
    parser.add_argument("--db", default=None, help="Database name (default: $DB_NAME or live_rebuilt_round5).")
    parser.add_argument("tests", nargs="*", help="Optional subset of test files to run.")
    args = parser.parse_args()

    use_psql = args.psql or args.rebuild or os.environ.get("BT_DB_TEST_MODE", "").lower() == "psql"
    db_name = args.db or os.environ.get("DB_NAME", "live_rebuilt_round5")

    if args.rebuild:
        rebuild_database(db_name, stop_before=args.stop_before)
    elif args.apply_from:
        apply_pending_migrations(db_name, args.apply_from, use_psql)
    if args.no_tests:
        sys.exit(0)

    if args.tests:
        test_files = [os.path.abspath(t) for t in args.tests]
    else:
        test_files = sorted(
            p for p in glob.glob(os.path.join(TEST_DIR, "*.sql"))
            if not os.path.basename(p).startswith("00_")
        )

    if not test_files:
        print("No SQL test files found in", TEST_DIR)
        sys.exit(0)

    failed = []
    passed = []

    for tf in test_files:
        if run_sql_file(tf, db_name=db_name, use_psql=use_psql):
            passed.append(tf)
        else:
            failed.append(tf)

    print("\n================================")
    print(f"Results: {len(passed)} passed, {len(failed)} failed")
    if failed:
        print("Failed tests:")
        for f in failed:
            print(f"  - {os.path.basename(f)}")
        sys.exit(1)
    print("All database tests passed successfully.")
    sys.exit(0)


if __name__ == "__main__":
    main()
