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
running the tests. A whole ``--rebuild`` then builds ``<db>_rollout`` in the order production gets
(hotfixes first, see ``rollout_order_check``) and runs the tests there too. Never point ``--rebuild``
at a real Supabase project.

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


# The rollout the account deletion batch gets. See rollout_order_check.
ROLLOUT_BATCH = "20261105000000"
ROLLOUT_HOTFIXES = ("20261105000500",)
# Files an operator may run again while following the chain. Each must be harmless the second time.
ROLLOUT_RERUN = ("20261105000500", "20261105000600", "20261105000700")
# Run by hand on live (2026-11-05). Live has no cost_control_templates table.
ROLLOUT_ALREADY_ON_LIVE = """
REVOKE TRUNCATE ON public.inquiries FROM anon, authenticated;
"""
# Live has drifted from the chain: read-only checks found no cost_control_templates table and
# neither function of 20261026120000. The drift scenario builds the chain without that file.
DRIFT_MISSING = ("20261026120000",)
# Tests that do not need what the drifted database lacks (42 and 43 test that migration's objects).
DRIFT_TESTS = ("36_", "37_", "38_", "39_", "40_", "41_", "44_", "45_", "46_", "47_", "49_")

# Live as measured read-only on 2026-11-05: exactly these two older files never ran, 000500 and
# REVOKE TRUNCATE on inquiries did, and cost_control_sub_categories holds 50 rows with no
# household_id column. The release runs the two first, then the batch.
LIVE_MISSING = ("20261026120000", "20261101000100")
# The production order of those, with 000600 and 000700 moved up: they close at once what
# 20261026120000 opens, so they run right after it, and again (harmlessly) after the tests.
LIVE_FIRST = ("20261026120000", "20261105000600", "20261105000700", "20261101000100")
# 46 rows come from the chain; live has 4 more, made through the API ('sub-' codes).
LIVE_SEED_SQL = """
INSERT INTO public.cost_control_sub_categories (parent_code, sub_code, name_en, name_ar) VALUES
    ('OPEX-MISC', 'sub-gym-membership', 'Gym membership', 'اشتراك النادي'),
    ('OPEX-MISC', 'sub-pet-food', 'Pet food', 'طعام الحيوانات'),
    ('OPEX-SHOPPING', 'sub-gifts', 'Gifts', 'هدايا'),
    ('OPEX-DINING', 'sub-work-lunch', 'Work lunch', 'غداء العمل');
DO $$
BEGIN
    IF (SELECT count(*) FROM public.cost_control_sub_categories) <> 50 THEN
        RAISE EXCEPTION 'live replica should hold 50 sub-category rows';
    END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS rollout_check;
CREATE TABLE rollout_check.sub_categories_before AS
    SELECT id, parent_code, sub_code, name_en, name_ar FROM public.cost_control_sub_categories;
"""


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


def rebuild_database(db_name, stop_before=None, skip=()):
    """Drop/recreate db_name and replay stubs + schema + migrations (psql mode only).

    ``stop_before``: replay only migrations whose filename sorts before this
    prefix (e.g. ``20261020`` rebuilds the chain as it was before that day).
    ``skip``: filename prefixes left out, to model a database that drifted from the chain.
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
    if skip:
        migrations = [m for m in migrations if not os.path.basename(m).startswith(tuple(skip))]
    steps += migrations
    print(f"Rebuilding {db_name}: {len(steps)} files (stubs, schema.sql, seed.sql, migrations)")
    for step in steps:
        if not run_sql_file(step, db_name=db_name, use_psql=True, quiet=True):
            raise SystemExit(f"Rebuild failed while applying {os.path.relpath(step, SUPABASE_DIR)}")
    print("Rebuild complete.")


def migrations_of(prefixes):
    """The migrations whose filename starts with one of these prefixes, in replay order."""
    return [m for m in migration_replay_order(os.path.join(SUPABASE_DIR, "migrations"))
            if os.path.basename(m).startswith(tuple(prefixes))]


def run_sql_text(sql, db_name):
    proc = subprocess.run(psql_command(db_name, True), input=sql.encode("utf-8"), capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(f"Rollout SQL failed: {proc.stderr.decode('utf-8', errors='replace')}")


def rollout_order_check(db_name, test_files, suffix="rollout", skip=(), seed_sql=None, first=()):
    """Builds the order production gets, and runs the tests against it. Returns what failed.

    Production has no migration history: files are run by hand. Some go out early as standalone
    hotfixes, so the chain later runs around them. A later file that redefines what a hotfix fixed
    would quietly undo it, and a filename-order rebuild can never see that, because the hotfix runs
    after it there. ``skip`` leaves older files out, for a database that drifted from the chain.
    ``seed_sql`` then makes it look like that database, and ``first`` lists files the release
    runs before the rest of the batch, in that order, after the hotfixes: older files, and batch
    files moved forward.

    Order: everything before the batch, less ``skip``; what has already run by hand on live; the
    hotfixes; ``first``; the rest of the batch in filename order; the tests. Then the files an
    operator may run again, which must be harmless, and the tests again. A migration that fails is
    reported as ``migration:<file>`` and ends the scenario.
    """
    rollout_db = f"{db_name}_{suffix}"
    print(f"\nRollout order check on {rollout_db}: hotfixes {', '.join(ROLLOUT_HOTFIXES)} before the batch"
          + (f", without {', '.join(skip)}" if skip else ""))
    rebuild_database(rollout_db, stop_before=ROLLOUT_BATCH, skip=skip)
    run_sql_text(ROLLOUT_ALREADY_ON_LIVE, rollout_db)
    if seed_sql:
        run_sql_text(seed_sql, rollout_db)

    def apply(paths, label):
        for path in paths:
            if not run_sql_file(path, db_name=rollout_db, use_psql=True, quiet=True):
                print(f"  {label} failed: {os.path.basename(path)}")
                return [f"migration:{os.path.basename(path)}"]
        return []

    def drop():
        # Throwaway, like the rebuild: no second database left behind.
        subprocess.run(["dropdb", "--if-exists", rollout_db], capture_output=True, text=True)

    hotfixes = migrations_of(ROLLOUT_HOTFIXES)
    # In the order given (the production run order), not in filename order.
    run_first = [m for prefix in first for m in migrations_of([prefix])]
    failed = (apply(hotfixes, "hotfix")
              or apply(run_first, "migration run first")
              or apply([p for p in migrations_of([ROLLOUT_BATCH[:8]]) if p not in hotfixes and p not in run_first],
                       "batch migration"))
    if failed:
        drop()
        return failed

    failed = [t for t in test_files if not run_sql_file(t, db_name=rollout_db, use_psql=True, quiet=True)]

    print("Running " + ", ".join(ROLLOUT_RERUN) + " again, as an operator following the chain might.")
    rerun_failed = apply(migrations_of(ROLLOUT_RERUN), "re-run")
    if rerun_failed:
        drop()
        return sorted(set(failed)) + rerun_failed
    failed += [t for t in test_files if not run_sql_file(t, db_name=rollout_db, use_psql=True, quiet=True)]

    drop()
    return sorted(set(failed))


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

    # A whole rebuild also proves the order production runs the files in.
    rollout_failed = []
    if args.rebuild and not args.stop_before and not args.tests:
        for suffix, skip, files, seed, first in (
            ("rollout", (), test_files, None, ()),
            ("drift", DRIFT_MISSING, [t for t in test_files if os.path.basename(t).startswith(DRIFT_TESTS)], None, ()),
            ("live", LIVE_MISSING, test_files, LIVE_SEED_SQL, LIVE_FIRST),
        ):
            scenario_failed = rollout_order_check(db_name, files, suffix=suffix, skip=skip, seed_sql=seed, first=first)
            print(f"Rollout order ({suffix}): {len(files)} test files, {len(scenario_failed)} failed")
            for f in scenario_failed:
                print(f"  - {suffix}: {os.path.basename(f)}")
            rollout_failed += [f"{suffix}:{os.path.basename(f)}" for f in scenario_failed]
        failed = sorted(set(failed) | set(rollout_failed))
        passed = [t for t in passed if t not in failed]

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
