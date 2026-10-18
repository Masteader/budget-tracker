# Code Quality & Testing Rules

## 1. Test-Driven Development (TDD) Workflow

1. **Write Tests First:** Whenever implementing a new model, service method, calculation helper, or complex widget, create unit or widget tests first.
2. **Verify Failure:** Run tests to confirm they fail for the intended reason before implementing the feature.
3. **Implement Feature:** Write the minimal clean implementation code to pass the tests.
4. **Verify Pass:** Run tests to verify all assertions succeed.
5. **Regression Verification:** Run `flutter test` across the entire test suite before concluding any feature task.

## 2. Zero Static Analysis Warnings

- Run `flutter analyze` inside `flutter_app/` before completing work.
- The project must compile with **zero errors and zero analyzer warnings**.
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
