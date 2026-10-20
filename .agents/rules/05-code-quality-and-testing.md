# Code Quality & Testing Rules

## 1. Test-Driven Development (TDD) Workflow

1. **Write Tests First:** Whenever implementing a new model, service method, calculation helper, or complex widget, create unit or widget tests first.
2. **Verify Failure:** Run tests to confirm they fail for the intended reason before implementing the feature.
3. **Implement Feature:** Write the minimal clean implementation code to pass the tests.
4. **Verify Pass:** Run tests to verify all assertions succeed.
5. **Regression Verification:** before concluding a task, run every suite the change touches (all of them for cross-cutting changes):
   - Flutter: `cd flutter_app && flutter test`
   - API: `cd ai_service && python -m pytest -v` (hermetic; no network, no real LLM)
   - Database: `python3 supabase/tests/run_tests.py --psql --rebuild --db <throwaway_db>` against a **local** PostgreSQL (libpq `PGHOST`/`PGPORT`/`PGUSER`); `--apply-from PREFIX` applies new migrations to an existing local replica, `--stop-before PREFIX` and `--no-tests` build a baseline. Never point the runner at a real Supabase project.
   - Web: `cd web_app && npm run lint && npm run build`
   - End-to-end: `tests/e2e/` (local services and mocks only)
6. **Database changes** ship as a new timestamped file in `supabase/migrations/` with a proof test in `supabase/tests/NN_*.sql` (the convention of the 20261019/20261020 batches).

## 2. Zero Static Analysis Warnings

- Run `flutter analyze` inside `flutter_app/` before completing work.
- The project must compile with **zero errors and zero analyzer warnings** (`No issues found!`), and `npm run lint` in `web_app/` must be clean.
- Keep dependencies updated and resolve all deprecation notices promptly.

## 3. No Placeholders / Production Integrity

- NEVER leave stubbed functions, empty dummy handlers, or `// TODO: implement later` comments in production code.
- Every interactive element (buttons, chips, sheet triggers, dialogs) must perform a real functional action or present an informative message to the user.
- Every state mutation must propagate reactively to UI listeners via Provider `notifyListeners()` or Supabase realtime streams.

## 4. Conventional Commits & Documentation Discipline

- Use conventional commit messages:
  - `feat(...)`: New functionality or capability
  - `fix(...)`: Bug fix or error resolution
  - `test(...)`: Adding or updating test cases
  - `docs(...)`: Documentation, spec, or plan updates
  - `refactor(...)`: Code refactoring without behavioral change
  - `chore(...)`: Tooling, build config, dependency bumps
- Keep `.md` implementation plans up-to-date with `- [x]` checklist markers as tasks are verified and committed.
