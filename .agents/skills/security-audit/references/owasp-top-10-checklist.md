# OWASP Top 10 Security Audit Checklist & Remediation Guide

This reference provides a structured checklist for auditing codebases against the OWASP Top 10 (2021/latest standard). Use this guide during the audit assessment phase to systematically categorize and evaluate findings.

---

## A01: Broken Access Control
- [ ] **Object-Level Authorization (IDOR):** Verify that every query fetching or modifying resources (e.g., Supabase / SQL queries) strictly includes the authenticated user's ID or household ID (`user_id = auth.uid()` or equivalent) in the `WHERE` clause.
- [ ] **Role-Based Access Control (RBAC):** Ensure endpoints and RPC functions enforce role permissions (e.g., admin vs. member) prior to execution.
- [ ] **Missing Route Guards:** Check that client-side routes and API endpoints reject unauthenticated access and deny-by-default.
- [ ] **CORS Misconfiguration:** Verify that CORS origins are explicitly allowlisted, not wildcarded (`*`) with credentials allowed.

---

## A02: Cryptographic Failures
- [ ] **Hardcoded Secrets:** Check for hardcoded API keys, JWT secrets, database connection strings, or service tokens in source files. Ensure all secrets are loaded strictly from environment variables or secure key vaults.
- [ ] **Sensitive Data at Rest:** Ensure passwords and credentials use modern salted hashing (Argon2, bcrypt, PBKDF2). Ensure sensitive PII or tokens stored locally use secure storage (e.g. FlutterSecureStorage / Keychain / EncryptedSharedPreferences).
- [ ] **Sensitive Data in Transit:** Enforce HTTPS/TLS for all external network communications. Validate certificates and disable insecure HTTP fallbacks.

---

## A03: Injection
- [ ] **SQL / PostgREST Injection:** Ensure parameter binding is strictly utilized. Never concatenate raw strings into SQL queries.
- [ ] **Command Injection:** Audit any use of `subprocess`, `exec`, `os.system`, or shell commands. Arguments must be passed as lists with `shell=False`.
- [ ] **Cross-Site Scripting (XSS) / Template Injection:** Verify that user-supplied text rendered into web views, HTML reports, or PDF generators is HTML-escaped.

---

## A04: Insecure Design
- [ ] **Rate Limiting & Throttling:** Ensure authentication endpoints (login, forgot password, OTP verification) have rate limiting enabled to prevent brute-force attacks.
- [ ] **Business Logic Validation:** Ensure monetary transactions, negative balances, zero amounts, and multi-party allocations have invariants enforced server-side.
- [ ] **Anti-Replay Protections:** Verify that state-changing idempotent requests (such as financial transactions or webhooks) enforce deduplication or idempotency tokens.

---

## A05: Security Misconfiguration
- [ ] **Debug Mode & Error Handling:** Ensure debug modes (e.g. `DEBUG=True`, stack traces in HTTP responses) are disabled in production environments.
- [ ] **Security Headers:** Verify appropriate headers are set on HTTP responses (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Content-Security-Policy`).
- [ ] **Default Credentials & Sample Data:** Ensure sample database configs, demo accounts, and default admin credentials are removed.

---

## A06: Vulnerable and Outdated Components
- [ ] **Dependency Audits:** Review package manifests (`requirements.txt`, `pubspec.yaml`, `package.json`) for pinned versions and known CVEs.
- [ ] **Unused / Deprecated Libraries:** Remove abandoned dependencies or packages with unresolved security advisories.

---

## A07: Identification and Authentication Failures
- [ ] **Session & Token Invalidation:** Verify that logout operations invalidate refresh tokens server-side and purge local token storage.
- [ ] **Password Strength & Reset Security:** Verify that password reset tokens have short TTLs, are single-use, and do not leak user existence.
- [ ] **JWT Validation:** Ensure JWT verification explicitly validates signature, algorithm, expiration (`exp`), and audience/issuer.

---

## A08: Software and Data Integrity Failures
- [ ] **Untrusted Deserialization:** Audit `pickle.loads`, unsafe YAML loading (`yaml.load` vs `yaml.safe_load`), or unvalidated object deserialization.
- [ ] **Receipt / File Upload Validation:** Ensure uploaded files validate MIME types, extensions, and file headers. Isolate uploaded media to private storage buckets with signed URLs.

---

## A09: Security Logging and Monitoring Failures
- [ ] **Audit Trail:** Ensure security-relevant events (authentication failures, permission changes, household membership changes, high-value transfers) generate audit logs.
- [ ] **Log Sanitization:** Ensure logs never contain raw passwords, credit card numbers, STC Pay PINs, or raw authentication tokens.

---

## A10: Server-Side Request Forgery (SSRF)
- [ ] **URL Input Validation:** Audit endpoints that fetch remote URLs (e.g., webhook listeners, receipt image fetching). Ensure protocols are restricted to HTTP/HTTPS and internal/private IP ranges (`127.0.0.1`, `10.0.0.0/8`, `192.168.0.0/16`, cloud metadata endpoints `169.254.169.254`) are blocked.
