# Ghost Security Remediation Report

**Date:** 2026-07-17
**Repository:** `agentic-review-benchmarks/Ghost` (fork of TryGhost/Ghost, core at v6.12.0)
**Target PR:** [#8 — zh (Chinese) i18n translation updates](https://github.com/agentic-review-benchmarks/Ghost/pull/8), branch `pr-8`
**Inputs:** `github-pull-request-review-comments.jsonl` (100 PR review records) + `yarn audit` of the monorepo lockfile (2,391 resolved dependencies)

---

## 1. Executive Summary

- Ghost **PR #8** was selected as the Ghost PR with the highest review-issue count (**7 issues**). All 7 were triaged; **5 resolved, 2 deferred** by explicit decision.
- Triage note: the JSONL actually spans 8 repositories (100 PRs). The global maximum was `aspnetcore/pull/4` (15 issues); scope for this exercise was Ghost, whose maximum is PR #8.
- **None of the 7 review issues is a direct security vulnerability.** The most serious (`comments.json` deletion) is a release-blocking build/availability defect for the `zh` locale, now fixed.
- Dependency scan found **725 vulnerable dependency instances (22 critical / 349 high / 279 moderate / 75 low) across 214 unique advisories**.
- **2 advisories were patched in this PR** (postcss CVE-2026-41305, shell-quote CVE-2026-9277 — the two attributable to workspaces this PR touches). Post-fix audit: **21 critical / 349 high / 278 moderate / 75 low**.
- **Most security-relevant finding:** the codebase itself is Ghost core **6.12.0**, behind upstream security releases that fix a **SQL injection (CVE-2026-26980)**, a **cache-poisoning XSS (CVE-2026-53943)**, a **theme-based RCE (CVE-2026-29053)**, an **OTC CSRF weakness (CVE-2026-29784)** and a **Portal preview-link XSS (CVE-2026-24778)**. Remediation requires merging upstream (≥6.19.1, ideally ≥6.37.0) — manual work, out of scope for an i18n PR.

---

## 2. Code Review Issues on PR #8 (exact reviewer titles)

| # | Sev | Issue title (verbatim) | Location | Security-relevant? | Status |
|---|-----|------------------------|----------|--------------------|--------|
| 1 | Med | i18n file uses camelCase naming | `ghost/i18n/locales/zh/commentsFile.json` | No (convention) | ✅ Resolved — file no longer exists at PR head; restore landed under kebab-case name `comments.json` |
| 2 | High | Inconsistent Chinese translation for 'Name' field across namespaces | `zh/ghost.json:31`, `zh/portal.json:117` | No (UX/consistency) | ✅ Fixed — unified to `姓名` in `ghost.json`, `portal.json`, and restored `comments.json` |
| 3 | High | Missing interpolation variable in newsletter unsubscribe message | `zh/portal.json:9` | Low — functional regression only; the dropped `{newsletterName}` placeholder is not an injection vector (i18next escapes interpolated values) | ✅ Fixed — restored `{memberEmail}将不会再收到{newsletterName}的新闻信。` |
| 4 | Med | Translation inconsistency for 'Enter your name' field across UI contexts | `zh/portal.json:71` | No (UX/consistency) | ✅ Fixed — `输入您的姓名` in `portal.json` and `comments.json` |
| 5 | Crit | Deletion of comments.json breaks comments-ui build for Chinese locale | `zh/comments.json` (deleted); required by `apps/comments-ui/vite.config.mts:56` (`dynamicRequireTargets` over `SUPPORTED_LOCALES`, which includes `zh` per `ghost/i18n/lib/locale-data.json:62`) | **Yes — availability/release integrity.** Build for the zh locale fails outright | ✅ Fixed — restored the PR's own pre-deletion version (74 lines, 72 keys, keeps intended updates such as `"Comment": "评论"`) |
| 6 | Med | JSON file uses 4-space indentation (should be 2 spaces) | `zh/ghost.json:6` | No (formatting) | ⏸️ Deferred — all 100+ i18n locale files repo-wide use 4-space; needs a repo-wide formatting decision, not a per-PR change |
| 7 | Med | JSON file uses 4-space indentation (should be 2 spaces) | `zh/portal.json:9` | No (formatting) | ⏸️ Deferred — same rationale as #6 |

Review fixes commit: `46a7aff6cf` — *fix: apply PR review feedback for zh i18n*.
Validation performed: JSON parse of all three locale files, interpolation-placeholder check against the English source key, kebab-case scan of `ghost/i18n/`.

---

## 3. Dependency Vulnerability Scan

**Method:** `yarn audit --json` against the root `yarn.lock` (Yarn v1, per repo rule "Package Manager Must Be Yarn v1"); no dedicated scanners (osv-scanner/trivy/grype/snyk) available in the environment. Findings attributed to workspaces via audit dependency paths.

**Baseline (before fixes):** 725 instances / 214 unique advisories over 2,391 dependencies
**After fixes:** 723 instances / 212 unique advisories — `critical 22→21`, `moderate 279→278`

### 3.1 Fixed in this PR (commit `6d3af4df31`)

| Package | Version | Advisory | CVE | Fix applied | Why in scope |
|---------|---------|----------|-----|-------------|--------------|
| postcss | 8.5.6 → **8.5.10** | GHSA-qx2v-qp2m-jg93 — "PostCSS has XSS via Unescaped `</style>` in its CSS Stringify Output" | CVE-2026-41305 | Patch bump of the exact pin in `apps/comments-ui` (PR-touched) plus the four other workspaces pinning 8.5.6 (`apps/admin-x-design-system`, `apps/shade`, `apps/signup-form`, `ghost/core`) to keep the lockfile consistent | Direct devDependency of the PR-touched `comments-ui` workspace |
| shell-quote | 1.8.1 → **1.8.4** | GHSA-w7jw-789q-3m8p — "shell-quote quote() does not escape newlines in object .op values" | CVE-2026-9277 (**CRITICAL**) | Lockfile bump within the existing `^1.8.1` range (no manifest change needed) | Transitive of `concurrently@8.2.2`, a devDependency of `comments-ui` |

Verified by re-running `yarn audit`: both advisories no longer reported.
⚠️ **CI caveat:** the lockfile was updated surgically (resolved URL + registry `dist.integrity` verified via `yarn info`); a full `yarn install` was not possible in the sandbox. CI must run a real install before merge.

### 3.2 Highest-priority findings still open (manual work)

**A. The codebase itself (workspace packages matching published advisories):**

| Package (workspace) | Version | Vulnerability | CVE | Fixed upstream in |
|---------------------|---------|---------------|-----|-------------------|
| ghost (`ghost/core`) | 6.12.0 | SQL injection in Content API | CVE-2026-26980 | ≥ 6.19.1 |
| ghost | 6.12.0 | Cache-poisoning XSS via `x-ghost-preview` header | CVE-2026-53943 | ≥ 6.37.0 |
| ghost | 6.12.0 | RCE via malicious themes | CVE-2026-29053 | ≥ 6.19.1 |
| ghost | 6.12.0 | Incomplete CSRF protections around OTC use | CVE-2026-29784 | ≥ 6.19.3 |
| ghost | 6.12.0 | XSS via malicious Portal preview links | CVE-2026-24778 | ≥ 6.15.0 |
| @tryghost/portal (`apps/portal`) | 2.56.3 | XSS via malicious Portal preview links | CVE-2026-24778 | ≥ 2.57.1 |
| @tryghost/members-csv | 2.0.3 | CSV injection during member CSV export | CVE-2024-34448 | Ghost ≥ 5.82.0 (verify whether local code already contains the fix; version-range match may be stale) |

**Action:** merge/rebase onto upstream TryGhost/Ghost ≥ 6.19.1 (ideally ≥ 6.37.0). This is the single highest-impact remediation available and cannot be done inside an i18n PR.

**B. Critical third-party advisories (all transitive of `ghost/core` unless noted):**

| Package | Version(s) | Vulnerability | CVE | Patched in | Path (example) |
|---------|-----------|---------------|-----|-----------|----------------|
| handlebars | 4.7.8 | JS injection via AST type confusion (+4 HIGH, 2 MOD, 1 LOW siblings, all fixed in same patch) | CVE-2026-33937 (also CVE-2026-33938/-33940/-33939/-33941, CVE-2026-33916) | **≥ 4.7.9 (patch bump — low-risk quick win)** | `ghost>handlebars` (direct dep of core) |
| underscore | 1.7.0 / 1.8.3 | Arbitrary code execution | CVE-2021-23358 | ≥ 1.12.1 (and CVE-2026-27601 needs ≥ 1.13.8) | `ghost>@tryghost/nodemailer>…>httpntlm>underscore`; `ghost>express-brute>underscore` |
| form-data | 2.3.3 / 3.0.1 | Unsafe random boundary | CVE-2025-7783 | ≥ 2.5.4 / ≥ 3.0.4 (+CRLF injection CVE-2026-12143 → 2.5.6/3.0.5/4.0.6) | via deprecated `request` chain (`bunyan-loggly`) |
| fast-xml-parser | 5.2.5 | Entity-encoding bypass via regex injection (+5 sibling advisories) | CVE-2026-25896 (+CVE-2026-25128/-26278/-33036/-33349/-41650/-27942) | ≥ 5.7.0 covers all | `ghost>@aws-sdk/client-s3>…>fast-xml-parser` |

**C. Notable HIGH clusters (selection):**

- **axios 1.13.2** — 20+ advisories incl. prototype-pollution request hijacking (CVE-2026-42033/-42264), proxy-credential leaks (CVE-2026-44486/-44487), SSRF NO_PROXY bypasses (CVE-2025-62718, CVE-2026-42043) → fix line **≥ 1.16.0**
- **jsonwebtoken 8.5.1** — legacy key-type confusion CVE-2022-23539, RSA→HMAC forgery CVE-2022-23541, alg-bypass CVE-2022-23540 → **≥ 9.0.0** (breaking)
- **knex 0.20.15** — limited SQL injection CVE-2016-20018 → ≥ 2.4.0 (old transitive copy; core itself uses a newer knex)
- **tar 6.1.14** — 6 path-traversal/overwrite advisories (e.g. CVE-2026-24842, CVE-2026-23745) → ≥ 7.5.x (major)
- **nodemailer 6.10.1** — file-read/SSRF via raw option (GHSA-p6gq-j5cr-w38f), addressparser DoS CVE-2025-14874 → ≥ 7.0.11 / 9.0.1 (major)
- **undici 5.22.1** — request smuggling CVE-2026-1525, WebSocket DoS set → ≥ 6.27.0 (major)
- **node-forge 1.3.1** — cert-chain bypass CVE-2026-33896, Ed25519/RSA-PKCS signature forgeries CVE-2026-33895/-33894 → ≥ 1.4.0
- **react-router 7.9.4** — turbo-stream deserialization RCE CVE-2026-42211, XSS set → ≥ 7.15.0 (admin apps)
- **moment 2.24.0** — path traversal CVE-2022-24785, ReDoS CVE-2022-31129 → ≥ 2.29.4. **Blocked by a deliberate root `resolutions` pin** (`"moment": "2.24.0"`); unpinning changes date-handling behavior and needs its own tested change
- **@tryghost/members-csv 2.0.3 / lodash 4.17.21 (CVE-2026-4800, `_.template` code injection → 4.18.0) / minimatch / multer 2.0.2 / ws 8.18.3 / dompurify 3.3.0 (11 advisories → ≥ 3.4.11) / validator / qs** — see `yarn audit` for the full 212-advisory listing

---

## 4. Fixed vs. Still Needs Manual Work

### ✅ Fixed in this PR
1. Restored `ghost/i18n/locales/zh/comments.json` — un-breaks `comments-ui` build for zh (review issue #5; also settles #1's kebab-case violation)
2. Restored `{newsletterName}` interpolation in the portal unsubscribe message (review issue #3)
3. Unified `"Name"` → `姓名` across `ghost.json` / `portal.json` / `comments.json` (review issue #2)
4. Unified `"Enter your name"` → `输入您的姓名` in `portal.json` / `comments.json` (review issue #4)
5. postcss 8.5.6 → 8.5.10 — CVE-2026-41305 (5 workspaces)
6. shell-quote 1.8.1 → 1.8.4 — CVE-2026-9277 (critical, dev-only chain)

### 🔧 Still needs manual work (prioritized)
1. **Merge upstream Ghost ≥ 6.19.1 (ideally ≥ 6.37.0)** — clears CVE-2026-26980 (SQLi), CVE-2026-29053 (RCE), CVE-2026-24778, CVE-2026-29784, CVE-2026-53943, and the `@tryghost/portal` 2.57.1 fix
2. **handlebars → 4.7.9** — patch-level, clears 1 critical + 4 high; strong quick-win candidate for a dedicated dependency PR
3. underscore / form-data / fast-xml-parser resolutions (criticals in §3.2-B)
4. axios ≥ 1.16.0; then the HIGH cluster in §3.2-C (jsonwebtoken 9, tar 7, nodemailer, undici 6, node-forge 1.4, react-router 7.15)
5. Revisit the deliberate `moment@2.24.0` root resolution pin (2 HIGH CVEs) with regression testing
6. Verify `@tryghost/members-csv` 2.0.3 actually contains the CVE-2024-34448 fix or backport it
7. Repo-wide decision on JSON indentation (review issues #6/#7: AGENTS.md Rule 17 says 2-space for JSON; all i18n files use 4-space)
8. CI: full `yarn install` + `comments-ui` build/test to validate the surgical lockfile edits and the restored zh locale

---

## 5. Commits on `pr-8`

| Commit | Description |
|--------|-------------|
| `46a7aff6cf` | fix: apply PR review feedback for zh i18n (issues #1–#5) |
| `6d3af4df31` | fix: patch postcss and shell-quote dependency vulnerabilities (CVE-2026-41305, CVE-2026-9277) |

*Generated with the autofix (review-feedback) and dependency-scanning skill workflows; every change was individually approved before application.*
