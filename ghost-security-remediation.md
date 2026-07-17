# Ghost Security Remediation Report — PR #8 (zh i18n) + Full Dependency Scan

- **Date:** 2026-07-17
- **Repository:** `agentic-review-benchmarks/Ghost` (Ghost monorepo mirror)
- **Target PR:** [`#8`](https://github.com/agentic-review-benchmarks/Ghost/pull/8) — upstream Ghost PR 25696 (Chinese locale translation updates)
  - Base: `base_pr_25696_20260125_1105` (`96253df719`)
  - Head reviewed: `6eb367bfb0` · Remediation commit: `e70c30e5e0` (branch `fix/pr8-review-feedback`)
- **Selection rationale:** PR #8 has the highest review-issue count (7) among the Ghost PRs in `github-pull-request-review-comments.jsonl`. (The file also contains 7 non-Ghost repos; the top Ghost PR was selected per triage owner's confirmation.)
- **Scanners:** OSV.dev API (querybatch + per-advisory detail, live DB) and `yarn audit` v1.22.22 (npm registry advisory DB), run against the root `yarn.lock` (4,383 unique `package@version` entries, workspaces `ghost/*`, `apps/*`, `e2e`).

---

## 1. Executive summary

| Area | Result |
|---|---|
| Code review issues on PR #8 | 7 total — **5 fixed** in commit `e70c30e5e0`, **2 deferred** as false positives (indentation rule conflicts with repo-wide convention) |
| Security-critical review issues | **0** of 7 are exploitable security defects; 1 is release-blocking (build break), 1 is a user-facing functional bug |
| Dependency scan (OSV, deduplicated) | **262 unique advisories** across **156 vulnerable `package@version` entries**: 16 CRITICAL / 115 HIGH / 101 MODERATE / 29 LOW / 1 unrated |
| Dependency scan (`yarn audit`, path-counted) | 22 critical / 349 high / 279 moderate / 75 low across 2,391 resolved dependency paths |
| PR-touched workspace (`@tryghost/i18n`) | **Clean** — runtime dep `i18next@23.16.8` and devDeps (`c8@10.1.3`, `i18next-parser@8.13.0`, `mocha@11.7.3`) have zero advisories |
| Dependency remediation applied | **None (report-only by decision):** the PR is i18n-only, and this environment (Node 18.20.4) cannot run Ghost's test suite (requires Node ^22.13.1). Prioritized fix plan in §5 |

---

## 2. Code review issues — status and security relevance

Issue titles are verbatim from the review feedback.

| # | Issue title (verbatim) | Location | Security relevant? | Status |
|---|---|---|---|---|
| 5 | Deletion of comments.json breaks comments-ui build for Chinese locale | `ghost/i18n/locales/zh/comments.json` | **Availability/release risk** — `apps/comments-ui/vite.config.mts:56` requires `comments.json` in `dynamicRequireTargets` for every supported locale; zh build fails. Not exploitable. | ✅ **Fixed** — file restored from base (74 lines, valid JSON) |
| 1 | i18n file uses camelCase naming | `ghost/i18n/locales/zh/commentsFile.json` | No — convention (repo Rule 10, kebab-case) | ✅ **Fixed** — the camelCase file does not exist on the final head; restoring kebab-case `comments.json` resolves the violation |
| 3 | Missing interpolation variable in newsletter unsubscribe message | `ghost/i18n/locales/zh/portal.json:9` | Marginal — users could not see *which* newsletter they unsubscribed from (notification-clarity issue, not exploitable) | ✅ **Fixed** — translation restored to `{memberEmail}将不会再收到{newsletterName}的新闻信。` |
| 2 | Inconsistent Chinese translation for 'Name' field across namespaces | `ghost.json:31` (`名字`) vs `portal.json:117` (`名称`) | No — UX/i18n consistency | ✅ **Fixed** — both unified to `姓名` |
| 4 | Translation inconsistency for 'Enter your name' field across UI contexts | `ghost/i18n/locales/zh/portal.json:71` | No — UX/i18n consistency | ✅ **Fixed** — `输入您的名字` → `输入您的姓名` |
| 6 | JSON file uses 4-space indentation (should be 2 spaces) | `ghost/i18n/locales/zh/ghost.json:6` | No — formatting | ⏸ **Deferred (false positive)** — every i18n locale JSON in the repo (en, fr, zh, incl. unchanged lines of this file) uses 4-space; re-indenting 2 lines would create internal inconsistency. Needs maintainer decision on Rule 17 vs. actual convention |
| 7 | JSON file uses 4-space indentation (should be 2 spaces) | `ghost/i18n/locales/zh/portal.json:9` | No — formatting | ⏸ **Deferred (false positive)** — same rationale as #6 |

**Verification performed:** all three modified/restored JSON files parse cleanly; automated check confirmed no translation string references an interpolation variable absent from its key. Ghost's `yarn lint:translations` could not run locally (workspace deps not installed); it should run in CI.

---

## 3. Dependency scan — scope and methodology

1. Parsed the root `yarn.lock` (34,726 lines) into 4,383 unique `package@version` pairs.
2. Queried **OSV.dev** `/v1/querybatch` for all pairs, then fetched full records for all 262 advisory IDs (severity, CVE aliases, fixed versions).
3. Cross-checked with **`yarn audit --json`** against `registry.npmjs.org` (completed on retry after a TLS drop on the default endpoint).
4. Mapped every vulnerable package to workspaces that declare it directly (`dependencies` / `devDependencies` / `resolutions`); all others are transitive.

Artifacts (local): `/tmp/osv-hits.json`, `/tmp/osv-details.json`, `/tmp/scan-aggregate.json`, `/tmp/yarn-audit.jsonl`.

### PR-scope result

The PR touches only `ghost/i18n`. That workspace is **clean**: `i18next@23.16.8` (runtime), `c8@10.1.3`, `i18next-parser@8.13.0`, `mocha@11.7.3` (dev) — zero advisories. The restored `comments.json` is consumed by `@tryghost/comments-ui`, whose vulnerable deps are dev/build-time only (see §4.2).

---

## 4. Dependency scan — findings

### 4.1 CRITICAL advisories (16 unique, all packages listed)

| Package@version | Advisories (CVE / GHSA) | Issue | Exposure | Fixed in |
|---|---|---|---|---|
| `handlebars@4.7.8` | CVE-2026-33937/-33938/-33939/-33940/-33941 (GHSA-2w6w-674q-4c4q et al.) | JavaScript injection via AST type confusion (incl. `@partial-block` tampering, dynamic partials) + DoS via malformed decorator | **Runtime, direct dep of `ghost` core — Ghost's theme/template engine. Highest-priority item.** | 4.7.9 |
| `form-data@2.3.3`, `@3.0.1` | CVE-2025-7783 (GHSA-fjxv-7rqg-78g4), CVE-2026-12143 (GHSA-hmw2-7cc7-3qxx) | Predictable multipart boundary (unsafe random); CRLF injection via unescaped field names | Runtime, direct dep of `ghost` core (also `form-data@4.0.4` HIGH for the CRLF issue) | 2.5.4/2.5.6, 3.0.4/3.0.5, 4.0.6 |
| `@xmldom/xmldom@0.8.3` | CVE-2026-41672/-41673/-41674, CVE-2022-39353 | XML parsing flaws incl. malformed-document acceptance | Transitive | 0.8.4+ per advisory set |
| `fast-xml-parser@5.2.5` | CVE-2026-25128, CVE-2026-33036, CVE-2026-26278, CVE-2026-25896 | Multiple parser vulnerabilities | Transitive | per-advisory (5.3.x line) |
| `protobufjs@7.5.4` | CVE-2026-44289/-44290/-44291/-44293 (+1 GHSA) | Prototype-pollution-class issues | Transitive | per-advisory |
| `pbkdf2@3.1.2` | CVE-2025-6545, CVE-2025-6547 | Crypto primitive returns predictable/uninitialized memory in edge cases | Transitive (crypto polyfill chain) | 3.1.3 |
| `cipher-base@1.0.4` | CVE-2025-9287 | Missing input validation in hash chain | Transitive | 1.0.5 |
| `sha.js@2.4.11` | CVE-2025-9288 | Missing type checks → hash rewind | Transitive | 2.4.12 |
| `underscore@1.7.0`, `@1.8.3` | CVE-2021-23358 (+CVE-2026-27601 HIGH) | Arbitrary code execution via `template` | Transitive (legacy chains) | 1.12.1 (2021 issue); 1.13.7+ (2026 issue) |
| `minimist@0.0.8` | CVE-2021-44906 | Prototype pollution | Transitive (legacy `mkdirp` chain) | 0.2.4 / 1.2.6 |
| `shell-quote@1.8.1` | CVE-2026-9277 | Command-string escaping bypass | Transitive | per advisory |
| `websocket-driver@0.7.4` | CVE-2026-54466 | Protocol handling flaw | Transitive | per advisory |
| `babel-traverse@6.26.0` | CVE-2023-45133 | Arbitrary code execution when compiling attacker-crafted code | Build-time (legacy Babel 6 chain) | @babel/traverse 7.23.2 |
| `growl@1.9.2` | CVE-2017-16042 | Command injection | Dev-only (legacy mocha chain) | 1.10.0 |
| `vitest@1.6.1`, `@3.2.4`, `@4.0.5` | CVE-2026-47429 (GHSA-5xrq-8626-4rwp) | Arbitrary file read + code execution when Vitest UI server is listening | Dev-only, direct devDep of all 13 `apps/*` incl. `comments-ui`/`portal` | 3.2.6 / 4.1.0 |

### 4.2 HIGH — direct dependencies of `ghost` core (runtime unless noted)

| Package@version | CVE(s) | Issue | Fixed in |
|---|---|---|---|
| `@tryghost/members-csv@2.0.3` | CVE-2024-34448 | **Ghost's own advisory**: CSV injection during member CSV export | Ghost ≥ 5.82.0 vendored version — verify monorepo copy carries the fix |
| `knex@0.20.15`, `@0.21.21` | CVE-2016-20018 | Limited SQL injection via crafted identifiers | 2.4.0 (major migration) |
| `jsonwebtoken@8.5.1` | CVE-2022-23539 | Unrestricted key type → legacy-key confusion | 9.0.0 (major) |
| `multer@2.0.2` | CVE-2026-3520, CVE-2026-5079, CVE-2026-2359, CVE-2026-3304 | 4× DoS (recursion, nested field names, resource exhaustion, incomplete cleanup) on upload handling | 2.1.0 / 2.1.1 / 2.2.0 |
| `nodemailer@6.10.1` | CVE-2025-14874, GHSA-p6gq-j5cr-w38f | addressparser DoS; `raw` option bypasses `disableFileAccess`/`disableUrlAccess` → arbitrary file read | 7.0.11 / 9.0.1 (major) |
| `jsonpath@1.1.1` | CVE-2026-1615 | Arbitrary code injection via unsafe eval of path expressions | 1.3.0 |
| `lodash@4.17.21` | CVE-2021-23337, CVE-2026-4800 | Code injection via `_.template` | 4.18.0 (also `lodash-es@4.17.21` in admin-x/shade) |
| `moment@2.24.0` | CVE-2022-24785, CVE-2022-31129 | Path traversal in `moment.locale`; ReDoS. **Pinned at root via `resolutions: {"moment": "2.24.0"}`** — deliberate legacy pin that must be revisited | 2.29.2 / 2.29.4 |
| `luxon@1.28.0` | CVE-2023-22467 | ReDoS | 1.28.1 / 3.2.1 |
| `tmp@0.0.28/0.0.33/0.1.0/0.2.5` | CVE-2026-44705 | Path traversal via unsanitized prefix/postfix | 0.2.6 |
| `semver@2.3.2`, `@5.7.1` | CVE-2022-25883, CVE-2015-8855 | ReDoS | 5.7.2 / 6.3.1 / 7.5.2 |
| `glob@10.4.5` | CVE-2025-64756 | CLI `-c/--cmd` command injection (`shell:true`) | 10.5.0 / 11.1.0 |
| `html-minifier@4.0.0` | CVE-2022-37620 | ReDoS — **no fixed version exists (package unmaintained)** | none — migrate to `html-minifier-terser` |

Other notable HIGHs: `nth-check@1.0.2` (CVE-2021-3803), `ws@7.5.9/8.11.0/8.18.3` (CVE-2024-37890, CVE-2026-48779), `undici@5.22.1` (CVE-2026-1526, CVE-2026-2229, CVE-2026-12151), `axios@1.13.2` (5 CVEs incl. CVE-2026-25639), `path-to-regexp@0.1.12/1.8.0/8.2.0` (CVE-2024-45296, CVE-2026-4867, CVE-2026-4926), `minimatch` family ×5 versions (CVE-2026-26996/-27903/-27904, CVE-2022-3517), `validator@7.2.0/13.12.0` (CVE-2025-12758, used by admin apps), `react-router@7.9.4` (7 advisories, admin-x-framework), `vite@5.4.20/7.1.12` (CVE-2026-53571, CVE-2026-39363/-39364 — dev server; devDep of all apps incl. comments-ui/portal), `storybook@8.6.14/9.1.10` (CVE-2025-68429, CVE-2026-27148, dev), `tar@6.1.14` (6 advisories), `ip@2.0.1` (CVE-2024-29415, no complete fix released), `moment` duplicate pin in `comments-ui` direct deps.

### 4.3 Notable MODERATE items (direct deps of `ghost` core)

- `dompurify@3.3.0` — CVE-2026-0540, CVE-2026-41238/-41239/-41240 (+2): sanitizer bypass classes. **DOMPurify is Ghost's XSS defense for rendered content — treat as high priority despite moderate CVSS.**
- `express-brute@1.0.1` — GHSA-984p-xq9m-4rjw: rate-limit bypass (brute-force protection component; unmaintained upstream).
- `js-yaml@3.14.1/4.1.0` — CVE-2025-64718, CVE-2026-53550; `file-type@16.5.4` — CVE-2026-31808; `postcss@7.0.39/8.5.6` — CVE-2023-44270, CVE-2026-41305 (build-time).

---

## 5. Fixed vs. needs manual work

### ✅ Fixed in this PR (commit `e70c30e5e0`)

1. Restored `ghost/i18n/locales/zh/comments.json` — un-breaks the `comments-ui` zh build (review issue **#5**) and resolves the kebab-case naming violation (**#1**).
2. Restored `{newsletterName}` interpolation in the portal unsubscribe message (**#3**).
3. Unified `"Name"` → `姓名` in `zh/ghost.json` and `zh/portal.json` (**#2**).
4. Aligned `"Enter your name"` → `输入您的姓名` in `zh/portal.json` (**#4**).

### ⏸ Needs manual work / decisions

| Priority | Item | Owner action |
|---|---|---|
| **P0** | `handlebars` → 4.7.9 (5 CRITICAL CVEs in the theme engine); `form-data` → 2.5.6 / 3.0.5 / 4.0.6; verify `@tryghost/members-csv` carries the CVE-2024-34448 fix | Dedicated dependency PR, validated by CI on Node ^22.13.1 |
| **P0** | `jsonpath` → 1.3.0 (code injection); `multer` → ≥2.2.0; `nodemailer` upgrade path (majors — review `raw` option usage) | Same dep PR; smoke-test mail + upload paths |
| **P1** | Lift root `resolutions` pin `moment@2.24.0` → 2.29.4 (confirm the original locale-related pin reason); `lodash` → 4.18.0; `tmp` → 0.2.6; `luxon`, `semver`, `glob` bumps; `dompurify` sanitizer update | Requires regression tests on date/locale handling and content sanitization |
| **P1** | Majors with breaking changes: `jsonwebtoken` 8→9, `knex` 0.21→2.4+ | Plan as separate migration work; not a quick bump |
| **P2** | Dev/build-only: `vitest` → 3.2.6/4.1.0, `vite` → patched lines, `storybook`, legacy Babel 6 / mocha chains (`babel-traverse`, `growl`, `minimist`, `underscore`) — many resolve only by upgrading the tools that drag them in | Batch in tooling-upgrade PR; low runtime risk |
| **P2** | No-fix packages: `html-minifier@4.0.0` (migrate to `html-minifier-terser`), `express-brute` (unmaintained — consider `rate-limiter-flexible`), `ip@2.0.1` | Replacement evaluation |
| Decision | Review issues **#6/#7**: Rule 17 (2-space JSON) contradicts the 4-space convention used by every i18n locale file in the repo | Maintainers: fix the rule or reformat all locale files repo-wide in a dedicated formatting PR |
| Note | Environment gap: local Node 18.20.4 vs required ^22.13.1 (`ghost/core` engines) prevented running the test suite; all dependency changes must be CI-validated | Infra |

---

## 6. Reproduction

```bash
# OSV scan
python3 parse_yarn_lock.py yarn.lock            # → package@version list (4,383)
POST https://api.osv.dev/v1/querybatch          # → 156 vulnerable entries / 262 advisories
GET  https://api.osv.dev/v1/vulns/{id}          # → severity, CVEs, fixed versions

# Registry cross-check
yarn audit --json --registry https://registry.npmjs.org
# → 22 critical / 349 high / 279 moderate / 75 low (path-counted, 2,391 deps)
```

*Generated during PR-#8 triage on 2026-07-17. OSV data reflects the live database on that date.*
