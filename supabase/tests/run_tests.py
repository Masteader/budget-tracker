#!/usr/bin/env python3
"""Database test runner for Supabase local Docker / CI."""

import os
import sys
import subprocess
import glob

def run_sql_file(file_path, db_name="live_rebuilt_round5", host="localhost", port="54329", user="postgres"):
    print(f"\n--- Running: {os.path.basename(file_path)} ---")
    
    # We execute via docker exec if container is available, else via psql directly
    cmd = [
        "docker", "exec", "-i", "budget_tracker_review_pg",
        "psql", "-U", user, "-d", db_name, "-v", "ON_ERROR_STOP=1"
    ]
    
    with open(file_path, "rb") as f:
        sql_content = f.read()

    proc = subprocess.run(cmd, input=sql_content, capture_output=True)
    stdout = proc.stdout.decode("utf-8", errors="replace")
    stderr = proc.stderr.decode("utf-8", errors="replace")
    
    if proc.returncode != 0:
        print(f"FAILED (exit code {proc.returncode}):")
        if stderr:
            print(stderr)
        if stdout:
            print(stdout)
        return False
    else:
        print("PASSED")
        combined = stdout + "\n" + stderr
        lines = [l for l in combined.splitlines() if "NOTICE:" in l or "DETAIL:" in l]
        for l in lines:
            print(f"  {l}")
        return True

def main():
    test_dir = os.path.dirname(os.path.abspath(__file__))
    test_files = sorted(glob.glob(os.path.join(test_dir, "*.sql")))
    
    if not test_files:
        print("No SQL test files found in", test_dir)
        sys.exit(0)

    db_name = os.environ.get("DB_NAME", "live_rebuilt_round5")
    failed = []
    passed = []

    for tf in test_files:
        ok = run_sql_file(tf, db_name=db_name)
        if ok:
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
