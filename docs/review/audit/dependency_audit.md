# Dependency and Supply-Chain Audit

Date: 2026-10-20. Base commit: `952098d`. This is a report only. No dependency file was changed.

Scope:
- `ai_service/requirements.txt`, `Dockerfile`, `docker-compose.yml`
- `web_app/package.json` and `package-lock.json`
- `flutter_app/pubspec.yaml` and `pubspec.lock`
- CDN-loaded scripts in `landing_page/*.html`, `ai_service/static/index.html` and `ai_service/_landing_impl.py`

## Method and tool versions

| Stack | What was run | Tools |
|---|---|---|
| Python | Installed `requirements.txt` into fresh scratch venvs on Python 3.11.17 (the Dockerfile version) and on 3.13.16. Ran `pip-audit -l` and `pip-audit -r requirements.txt`. Checked the version floors (`>=` lower bounds) against the OSV API. Ran the hermetic test suite against the latest resolved versions. Built a hashed lock as a preview (`uv pip compile --generate-hashes`), not committed. | pip 26.2.2, pip-audit 2.10.1, uv 0.11.32, pipdeptree |
| Node | `npm ci`, `npm audit --omit=dev`, `npm audit`, `npm outdated`, `npm audit signatures`, plus a check of lockfile integrity and hosts | node 22.22.0, npm 10.9.4 |
| Flutter | `flutter pub get --enforce-lockfile` (the lock was not changed), `flutter pub outdated` and `--json --show-all` (discontinued, retracted and advisory flags), then all 152 hosted `pubspec.lock` packages through `https://api.osv.dev/v1/querybatch` with ecosystem `Pub`. The OSV query was checked against a known-vulnerable control (`http 0.12.2` correctly returns GHSA-4rgh-jx4f-qfcq). | Flutter 3.47.7, Dart 3.13.5 |

Resolved Python set: 95 packages, the same on 3.11 and 3.13. Main versions: fastapi 0.156.3, starlette 1.9.0, pydantic 2.14.1, litellm 1.106.1, supabase 2.33.0 (postgrest, realtime, storage3 and supabase-auth also 2.33.0), uvicorn 0.54.0, httpx 0.28.1, redis 8.1.0, reportlab 5.0.1, python-jose 3.5.0, PyJWT 2.15.1 (transitive), cryptography 50.0.2.

Test results with the latest-resolved set: **584 passed on Python 3.11 and 584 passed on Python 3.13**. The current floating resolution therefore works today.

---

## Findings by severity

| ID | Severity | Stack | Finding | Reachable? | Action |
|---|---|---|---|---|---|
| DEP-01 | **High** (supply chain) | Python | No lock, constraints or hashes. Every requirement is `>=` with no upper bound. The `litellm>=1.40.0` range includes **litellm 1.82.7 and 1.82.8, which contained credential-stealing malware** (MAL-2026-2144 / PYSEC-2026-2), and 1.40.0 itself, which has 59 OSV records (several Critical). | The malware runs on `import litellm`, so it is fully reachable for any build that resolved to those versions. Today's resolution (1.106.1) is clean. | Add a hashed lock and install with `--require-hashes`. Raise the floors. Check the deployed image (see below). |
| DEP-02 | **Medium** | Python | `python-jose 3.5.0`: **CVE-2026-85394 / GHSA-3qf3-8w2g-rqmx / PYSEC-2026-4298** (an incomplete fix for CVE-2024-33663, an HMAC/asymmetric algorithm-confusion bypass using DER public keys). Rated Critical by OSV. **No fixed version exists.** The library is minimally maintained. | **Not reachable in the current `auth.py`** (reasoning below) | Migrate `auth.py` to PyJWT, which is already installed through `supabase-auth`. Then drop `python-jose[cryptography]`. |
| DEP-03 | **Medium** (if deployed) | Web | `landing_page/index.html:108` and `landing_page/mobile.html:11` load `https://cdn.tailwindcss.com?plugins=forms,container-queries`: no version, no SRI, and the script runs at runtime with full DOM access. `index.html` contains the VIP form that posts to the API. | Yes, if these pages are served. They are listed as prototypes in WEB-13. | Precompile the CSS with the `web_app` Tailwind toolchain. A versioned CDN URL is only a stop-gap. |
| DEP-04 | Low | Python | `ecdsa 0.19.2`: **CVE-2024-23342 / GHSA-wj6h-64fc-37mp** (Minerva timing attack on P-256 signing). No fix is planned upstream. | No. python-jose selects the `cryptography` backend when it is installed (confirmed: `jose.backends.ECKey` is `CryptographyECKey`), and the service only verifies signatures. The advisory covers signing and ECDH. | The package goes away with the DEP-02 migration (`ecdsa` is pulled in only by python-jose). |
| DEP-05 | Low | Node | 7 dev-only advisories (5 high, 2 moderate), all from the `tailwindcss@3.4.19` build chain: `braces 3.0.3`, **GHSA-vfj7-8cjw-p6xm** (CVSS 7.5, no fixed `braces` release, so chokidar, micromatch and fast-glob are also flagged), and `postcss-selector-parser 6.1.4`, **GHSA-rj75-hqrm-r3gf** (CVSS 5.9, fixed in 7.1.6). `npm audit --omit=dev` finds **0**. | No. These only run at build time, on developer-controlled content globs and CSS. Nothing ends up in the shipped bundle. | Plan a Tailwind 4 migration. Do not run `npm audit fix --force` blindly (see below). |
| DEP-06 | Low | Docker | Floating base tag `python:3.11-slim` with no digest. `pip install --upgrade pip` is unpinned. No hash checking. Test-only packages (pytest, respx, fakeredis, pytest-asyncio) ship in the production image. The "~200MB" comment is wrong: site-packages alone is about 440 MB, and litellm accounts for 170 MB of it. | Partly. The test tools are dead weight in production, and pytest CVE-2025-71176 is local-only. | Pin the base image by digest. Split the requirements. Install from the lock with `--require-hashes`. |
| DEP-07 | Low | Flutter | Declared but never imported: `flutter_local_notifications` (also the most outdated package, 17.2.4 against 22.3.2) and `timeago`. `intl: any` is unconstrained. The SDK constraint `>=3.3.0` does not match the lock, which needs Dart `>=3.12.0` and Flutter `>=3.44.0`. | Unused plugins still add native code and manifest entries. | Remove the two unused packages. Set `intl: ^0.20.2` and `sdk: ^3.12.0`. |
| DEP-08 | Low | Flutter | 14 packages are held back by major-version constraints, and 36 more can move to newer versions without any `pubspec.yaml` change. **0 OSV advisories, 0 discontinued, 0 retracted** among 152 hosted packages. | No known vulnerabilities | Run `flutter pub upgrade` for the lock-only updates (supabase_flutter 2.17.2 to 2.18.3 and others). Schedule the majors (table below). |
| DEP-09 | Info | Python | The floors allow other known-vulnerable versions: `python-dotenv<1.2.2` (**CVE-2026-28684**, symlink in `set_key`), `pytest<9.0.3` (**CVE-2025-71176**, tmpdir). These versions are only installed when something holds the resolver back. | python-dotenv: no (only `load_dotenv` is used, never `set_key`). pytest: local only. | Raise the floors when adding the lock. |
| DEP-10 | Info | Web | Google Fonts stylesheets on every page, with no SRI. That is expected for dynamic CSS from a first-party Google domain, but it sends each visitor's IP address to Google. The Flutter app does the same at runtime through `google_fonts` (no bundled fonts). | Privacy only (PDPL) | Optional: self-host the fonts (Cairo, IBM Plex Sans Arabic, Outfit) as assets. |
| DEP-11 | Info | Compose | `version: "3.9"` is obsolete (Compose only warns). `env_file: .env` is mandatory, so `docker compose up` fails without it. There is no Redis service, so `REDIS_URL` is unset and the limiter uses per-process memory (fine for one process). The port is published on all interfaces. | Local development only. Production runs on Railway. | Optional cleanups. Add a `redis` service if compose is ever used for multi-instance tests. |

---

## Python details (`ai_service`)

### DEP-01: no lock, floors only, and the litellm malware release

`requirements.txt` has 14 direct requirements, all of the form `>=X`. Each build resolves to whatever is newest on PyPI that day. Concretely:

- The **litellm** floor `>=1.40.0` allows:
  - **1.82.7 and 1.82.8 (MAL-2026-2144 / PYSEC-2026-2)**, published on 2026-03-24 with a stolen PyPI token after the Trivy compromise. The payload runs on import. It harvests environment variables, `.env` files, SSH keys and cloud metadata tokens, sends them to `models.litellm[.]cloud`, and installs a systemd persistence unit.
  - **1.40.0 itself**, which has 59 OSV records, including:
    - GHSA-gppg-gqw8-wh9g / CVE-2024-5751 (eval RCE, Critical, fixed in 1.40.16)
    - GHSA-4xpc-pv4p-pm3w / CVE-2026-49468 (host-header authentication bypass, Critical, fixed in 1.84.0)
    - GHSA-6wvf-77m9-58rm / CVE-2026-37004 (SSTI, Critical, fixed in 1.83.7)
    - GHSA-3cv6-jpf6-8222 / CVE-2026-84377 (SSRF and credential exfiltration, fixed in 1.96.2)

  Reachability: almost all of these records concern the **LiteLLM Proxy server**: its admin UI, SSO, MCP, guardrails and `/prompts` endpoints. This service uses only the SDK (`litellm.completion` in `chat_parser.py`, `receipt_scanner.py` and `support_agent.py`). It does not install the `[proxy]` extra and never starts the proxy. So the CVEs are **not reachable** at any version. **The malware is reachable at any version that contains it.**
- The git history begins on 2026-10-19 (it was squashed), so this repository cannot show whether any environment was built during the malware window.
  - **Owner check:** run `pip show litellm` in the running Railway container, or look at old build logs and any developer `.venv` created in late March 2026.
  - If 1.82.7 or 1.82.8 ever appears, treat the host as compromised and rotate every secret it held: `SUPABASE_SECRET_KEY` / service role key, `SUPABASE_JWT_SECRET`, `GOOGLE_API_KEY`, `WEBHOOK_SECRET`, `RESEND_API_KEY` and any Railway token.
- Range of packages that could move to a breaking new major version through these unbounded floors:

| Requirement | Floor | Resolves today | Major-version exposure |
|---|---|---|---|
| `fastapi>=0.111.0` | 0.111.0 | 0.156.3 | FastAPI is still 0.x, so any minor release may break. It now pulls in **starlette 1.9** (a starlette major), which already warns "Using `httpx` with `starlette.testclient` is deprecated; install `httpx2`". A future starlette release could break the test suite. |
| `pydantic>=2.7.0` | 2.7.0 | 2.14.1 | No upper bound, so a future pydantic 3 would be installed automatically. FastAPI and litellm cap at `<3`, which would make the resolver fail or backtrack instead. |
| `supabase>=2.16.0` | 2.16.0 | 2.33.0 | supabase-py 3.x would arrive automatically. `postgrest_compat.py` exists only because postgrest behaviour already changed between minors. Deprecation warnings for `timeout` and `verify` already show up in tests. |
| `litellm>=1.40.0` | 1.40.0 | 1.106.1 | Releases almost daily with a large transitive tree (boto3, openai 2.x, huggingface_hub 1.x, tokenizers, tiktoken, jinja2, aiohttp). It is the highest-risk dependency, as the malware above shows. |
| `redis>=5.0.0` | 5.0.0 | **8.1.0** | Already three majors past the floor. Tests pass with fakeredis 2.40, but nothing pins this. |
| `reportlab>=4.0.0` | 4.0.0 | **5.0.1** | Major already crossed. `tests/test_pdf_statement.py` passes. Pulls in pillow 13, which requires Python 3.11+. |
| `pytest-asyncio>=0.23.0` | 0.23.0 | **1.4.0** | Major already crossed (strict mode by default). Tests pass. |
| `uvicorn[standard]>=0.30.0`, `httpx>=0.27.0` | | 0.54.0, 0.28.1 | Both are 0.x and may break on any minor. |

**Would a lock or constraints file help? Yes.** It is the main fix for DEP-01 and DEP-09. Recommended approach:

1. Keep `requirements.in` (or the current `requirements.txt`) with the direct dependencies. Raise these floors:
   - `litellm>=1.96.2,<2`: covers the newest fixed advisory and is past the malicious versions.
   - `python-dotenv>=1.2.2`
   - `pytest>=9.0.3`
   - `supabase>=2.16.0,<3`
   - `pydantic>=2.7,<3`
2. Generate the lock: `uv pip compile requirements.in --python-version 3.11 --generate-hashes -o requirements.lock`. This works today: it produced 95 pins in the dry run, and the preview was not committed.
3. In the Dockerfile, use `pip install --require-hashes --no-deps -r requirements.lock`.
4. Move pytest, pytest-asyncio, respx and fakeredis to `requirements-dev.txt` so they stay out of the production image.

Upgrade risk: low. The resolved set already passes all 584 tests. A lock freezes that set; it does not change it.

### DEP-02: python-jose (CVE-2026-85394)

The advisory works like this: python-jose's HMAC key wrapper accepts an asymmetric public key in DER form as if it were an HMAC secret. An attacker who knows the public key can then forge an HS256 token, but only when the verifier passes the public key to `jwt.decode` without restricting `algorithms`.

Why the current code is not exposed (`ai_service/auth.py`, `_decode_token`):
- It reads the header `alg` and branches on it explicitly.
- `ES256` uses a JWKS key filtered to `kty == "EC"`, `crv == "P-256"` and `alg == "ES256"`, with `algorithms=["ES256"]`.
- `HS256` uses `SUPABASE_JWT_SECRET` (a shared secret, never a public key), with `algorithms=["HS256"]`.
- Any other `alg` is rejected before verification.
- The public key is therefore never handed to the HMAC path.

Remaining risk: a future refactor could pass a single key object with both algorithms, or `alg` could be read from the token. There is also no upstream fix, so any later variant will not be patched.

Recommendation: migrate `auth.py` to **PyJWT**. It is already installed (PyJWT 2.15.1, required by `supabase-auth>=2.12`).
- `jwt.PyJWK(jwk_dict)` replaces `jose.jwk.construct`.
- `jwt.decode(..., algorithms=[...], audience=..., issuer=..., options={"require": ["exp", "iat", "sub"]}, leeway=30)` replaces the jose call.
- `jwt.get_unverified_header` has the same name.

Then remove `python-jose[cryptography]`. That also removes `ecdsa`, `rsa` and `pyasn1` (closing DEP-04).

Upgrade risk: medium-low. About 60 lines change in one module, and `tests/test_jwt_hardening.py` covers the alg allow-list, `kid` handling, JWKS throttling and the exp, iat, sub, aud, iss and role checks. Watch for small differences in exception types: PyJWT raises `jwt.PyJWTError` subclasses, not `JWTError`.

### Python version

- The Dockerfile uses 3.11, which receives security fixes until 2027-10. The resolved set and the test suite also work unchanged on **3.13**, so moving the base image to `python:3.12-slim` or `python:3.13-slim` is low risk.
- The comment `# Compatible with Python 3.10+` in `requirements.txt` is out of date. starlette 1.9 and pillow 13 require Python >=3.11, so on 3.10 pip would resolve to a different, untested set of older versions. Change the comment to 3.11+, or add `python_requires` / `.python-version`.

---

## Node details (`web_app`)

- `npm audit --omit=dev`: **0 vulnerabilities.** The runtime dependencies are react 19.3.1, react-dom 19.3.1, framer-motion 14.3.0 and canvas-confetti 1.9.4. `clsx` is declared but not imported anywhere in `src/`.
- Lockfile health: lockfileVersion 3 with 153 entries. Every entry resolves from `registry.npmjs.org` and has an `integrity` hash. `npm audit signatures`: 110 packages have verified registry signatures and 29 have verified attestations. The only install script belongs to `fsevents` (optional, macOS only).
- Full `npm audit` (DEP-05): every advisory comes through the build-time `tailwindcss@3.4.19` chain:

| Package | Installed | Advisory | Fixed in | Path |
|---|---|---|---|---|
| braces | 3.0.3 | GHSA-vfj7-8cjw-p6xm (high, 7.5, stack-exhaustion DoS) | **no fixed release** (3.0.3 is the latest on npm) | tailwindcss > chokidar / micromatch / fast-glob > braces |
| postcss-selector-parser | 6.1.4 | GHSA-rj75-hqrm-r3gf (moderate, 5.9, quadratic CPU) | 7.1.6 | tailwindcss > postcss-nested 6.2.0 > postcss-selector-parser |

npm's suggested fix is `tailwindcss@4.3.3`, a breaking major. Tailwind 4:
- moves configuration from `tailwind.config.js` into CSS (`@import "tailwindcss"`, `@theme`)
- replaces the PostCSS plugin with `@tailwindcss/postcss` or `@tailwindcss/vite`
- makes `autoprefixer` unnecessary
- renames some utilities (shadow, rounded and ring scales)

Risk: medium. The whole landing UI has to be checked visually. Because nothing here is reachable at runtime, this can be scheduled rather than done urgently. An `overrides` entry forcing `postcss-selector-parser@^7.1.6` under `postcss-nested@6` is not recommended: it crosses a major of the parser API.
- `npm outdated`:

| Package | Current | Latest | Note |
|---|---|---|---|
| tailwindcss | 3.4.19 | 4.3.3 | Major; see above |
| typescript | 6.0.3 | 7.0.2 | Major (native compiler); `tsc -b` must be re-checked |
| @types/node | 24.19.2 | 26.6.5 | Keep it matched to the Node major used for builds |
| framer-motion | 14.3.0 | 14.4.0 | Minor; safe |
| oxlint | 1.88.0 | 1.89.0 | Minor; safe |
| postcss | 8.5.30 | 8.5.31 | Patch; safe |

- The production copy of this app is the built bundle in `ai_service/static/`. Rebuild and re-copy it after any upgrade, or the served files will not change.

## Landing pages and CDN scripts (DEP-03, DEP-10)

| File | External resource | Pinned? | SRI? |
|---|---|---|---|
| `landing_page/index.html:108` | `<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries">` | **No** (always the latest Play CDN build) | **No** |
| `landing_page/mobile.html:11` | same | **No** | **No** |
| `landing_page/*.html`, `web_app/index.html`, `ai_service/static/index.html`, `ai_service/_landing_impl.py` | Google Fonts CSS (`fonts.googleapis.com/css2?...`) | Not applicable (dynamic CSS) | No (cannot be used with dynamic CSS) |

`ai_service/static/index.html` loads only self-hosted, hashed bundles (`/assets/index-*.js`), and `_landing_impl.py` loads no third-party JavaScript. Both are fine.

Tailwind documents the Play CDN as development-only. If the CDN or that URL were compromised, the attacker would get script execution on the landing page and could read or redirect the VIP form submission. Fix: compile the CSS at build time. The `web_app` toolchain already exists. At minimum, pin a version path such as `cdn.tailwindcss.com/3.4.17`. This is already tracked as WEB-13 (Low) in `ui_web.md`. It should become Medium if `landing_page/` is deployed publicly.

---

## Flutter details (`flutter_app`)

- OSV: **0 advisories** across all 152 hosted packages in `pubspec.lock` (5 SDK packages excluded).
- `pub outdated --json`: no package is discontinued, retracted, or flagged `isCurrentAffectedByAdvisory`.
- `flutter pub get --enforce-lockfile` succeeded, so the lockfile matches `pubspec.yaml`.

Upgrades that need only the lockfile (`flutter pub upgrade`, low risk, no `pubspec.yaml` change):

| Package | Current | Available |
|---|---|---|
| supabase_flutter | 2.17.2 | 2.18.3 |
| supabase | 2.16.1 | 2.16.5 |
| gotrue | 2.27.2 | 2.27.3 |
| realtime_client | 2.13.0 | 2.13.2 |
| storage_client | 2.8.0 | 2.8.1 |
| app_links | 7.2.1 | 7.2.2 |
| image_picker | 1.2.3 | 1.2.4 |
| sqflite | 2.4.4 | 2.4.4+2 |
| shared_preferences | 2.5.5 | 2.5.6 |
| url_launcher | 6.3.2 | 6.3.3 |

There are about 26 more transitive updates of the same kind. The Supabase client packages cover authentication and session refresh, so these updates are worth taking even without a published advisory.

Upgrades that need a new major version in `pubspec.yaml`:

| Package | Current | Latest | Use in `lib/` | Upgrade risk |
|---|---|---|---|---|
| flutter_local_notifications | 17.2.4 | 22.3.2 | **Not imported** | None. **Remove it** (it also removes its platform packages and transitive `timezone 0.9.4`). |
| timeago | 3.7.1 | (current) | **Not imported** | None. **Remove it.** |
| permission_handler | 11.4.0 | 13.0.2 | 5 files | Medium. The Android 14/15 permission API and manifest changes need re-testing on a device. |
| google_fonts | 6.3.3 | 9.0.0 | 62 files | Low to medium. API mostly stable. Fonts are fetched at runtime from `fonts.gstatic.com`; the package checks the file hash. Bundling the font files would also cover DEP-10. |
| fl_chart | 0.68.0 | 1.2.0 | 1 file | Low to medium. 1.0 changed some constructor and touch APIs. |
| shimmer | 3.0.0 | 4.0.0 | 1 file | Low |
| connectivity_plus | 7.3.1 | 7.3.2 | 1 file | Patch only (`Resolvable`) |
| flutter_lints (dev) | 4.0.0 | 6.0.0 | | Low risk, but it turns on new lints. AGENTS.md requires zero `flutter analyze` warnings, so fix those in the same change. |

Other Flutter notes:
- `intl: any`: `flutter_localizations` pins it in practice (0.20.2 to 0.20.3). Still, set `intl: ^0.20.2` so the constraint documents the real version.
- `environment: sdk: '>=3.3.0 <4.0.0'` does not match the lock's `dart: ">=3.12.0"` and `flutter: ">=3.44.0"`. Tighten it to `sdk: ^3.12.0` and add `flutter: ">=3.44.0"` so older toolchains fail with a clear message.
- `android/gradle/wrapper/gradle-wrapper.properties` has no `distributionSha256Sum`. Add it to pin the Gradle 9.3.1 distribution hash. Low priority.

---

## Docker and Compose (DEP-06, DEP-11)

Already in good shape:
- multi-stage build, with `gcc` only in the builder stage
- non-root `app` user
- `HEALTHCHECK`
- `.dockerignore` excludes `.env*`, tests and dev scripts (the API-25 fix)

Gaps:
1. `FROM python:3.11-slim` (both stages) is a floating tag. Pin it by digest (`python:3.11-slim@sha256:...`) and let Renovate or manual review bump it. Consider moving to 3.12 or 3.13 (tests pass on 3.13).
2. `pip install --upgrade pip` installs whatever pip is current. Pin it, or skip the upgrade when installing from a hashed lock.
3. `pip install -r requirements.txt` has no hashes (see DEP-01). Use `--require-hashes` with a lock file.
4. Test dependencies are installed into the runtime image. Split them into `requirements-dev.txt`.
5. The image-size comment (~200MB) is inaccurate: about 440 MB of site-packages, of which litellm is 170 MB, botocore 31 MB and cryptography 16 MB. A smaller LLM client (calling the Gemini REST API directly with the httpx already present) would remove most of the tree and most of the supply-chain risk. That is an architecture decision and is listed here as an option only.

Compose: see DEP-11. None of these affect the Railway deployment.

---

## Prioritised actions

1. **Now (owner check, no code):** confirm that the deployed `ai_service` image and any developer venv never had litellm 1.82.7 or 1.82.8. Use `pip show litellm` in the container and the build logs from around 2026-03-24. If either version is found, rotate all secrets in that environment.
2. **Next change (low risk):**
   - Add `requirements.lock` with hashes and install with `--require-hashes` in the Dockerfile.
   - Raise the floors: litellm `>=1.96.2,<2`, python-dotenv `>=1.2.2`, pytest `>=9.0.3`; add `<3` caps on supabase and pydantic.
   - Split out dev requirements.
   - Pin the Docker base image by digest.
3. **Next change (medium-low risk):** migrate `auth.py` from python-jose to PyJWT, and remove python-jose (together with its transitive ecdsa, rsa and pyasn1).
4. **Flutter (low risk):**
   - Remove `flutter_local_notifications` and `timeago`.
   - Run `flutter pub upgrade` for the lock-only updates (the Supabase stack).
   - Pin `intl` and tighten the SDK constraint.
5. **Landing pages:** replace the Tailwind Play CDN with build-time CSS before `landing_page/` is served publicly.
6. **Planned majors:** Tailwind 4 (this clears all 7 dev-only npm advisories), TypeScript 7, permission_handler 13, fl_chart 1.x, google_fonts 9, flutter_lints 6. Do them one per change and test each on a device or in a browser.
7. **Ongoing:** the CI workflow was removed at the owner's request (`1546504`), so nothing re-runs these checks. Run `pip-audit -r requirements.lock`, `npm audit --omit=dev` and an OSV scan of `pubspec.lock` before each release, or enable Dependabot or Renovate security-only alerts. Those alerts are repository settings, not a workflow.
