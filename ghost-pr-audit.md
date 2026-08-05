# Ghost — Pull Request Review Audit

**Source data:** `github-pull-request-review-comments.jsonl`
**Scope:** all records where `repo == "Ghost"` — 13 PRs, 63 findings
**Upstream under review:** `agentic-review-benchmarks/Ghost` (fork of `TryGhost/Ghost`)
**Date:** 2026-08-06

---

## Severity rubric

Findings are triaged into three tiers. The tiers are about *consequence*, not about how much text the original reviewer wrote.

| Tier | Meaning | Merge impact |
|---|---|---|
| **BLOCKER** | Process crash, security control removed, build/CI failure, persisted data corruption, or irreversible external harm (email sent, domain reputation burned). | Hard-block. Do not merge under any circumstance. |
| **REQUIRED** | A real defect users will hit. Recoverable and non-catastrophic, but shipping it is a known-bad decision. | Must be fixed before ship. |
| **SUGGESTION** | Lint, style, convention, or defensive nits. Includes findings that are weak or outright wrong. | Never gate a merge on these. |

---

## Executive summary

**All 13 PRs are DO NOT MERGE.** Not one is clean. That is the single most important sentence in this document.

| Metric | Count |
|---|---|
| PRs audited | 13 |
| Total findings | 63 |
| **BLOCKER** | **15** |
| **REQUIRED** | 21 |
| SUGGESTION | 27 |
| PRs with ≥1 blocker | 10 of 13 |
| PRs with zero substantive defects | **0** |

43% of all findings (27/63) are cosmetic. That is the noise floor of this review set — style rules about semicolons, quote characters, and `var`. Meanwhile 15 findings are genuine merge-stoppers. Anyone reading these reviews linearly will spend nearly half their attention on quote characters while a JWT signature check sits removed three lines down. **Read the blocker column first; the style findings can be handled by a formatter and should never have been raised as review comments at equal weight.**

### Verdict table

| PR | Area | B | R | S | Verdict | Most critical problem |
|---|---|:-:|:-:|:-:|---|---|
| [1](#pr-1--boot-sequence) | `boot.js` service init | 1 | 2 | 1 | **DO NOT MERGE** | Ghost crashes on boot — `scheduling.init()` lost its required `apiUrl`, constructor throws `IncorrectUsageError`. |
| [2](#pr-2--comments-ui-reply-forms) | comments-ui forms | 2 | 1 | 1 | **DO NOT MERGE** | Reply threading writes the wrong `in_reply_to_id`, silently corrupting conversation hierarchy in the database. |
| [3](#pr-3--domain-warming-thresholds) | DomainWarmingService | 0 | 3 | 1 | **DO NOT MERGE** | Three independent boundary/comparison bugs in one email rate-limit function; every documented threshold is off. |
| [4](#pr-4--admin-comments-list) | admin comments list | 1 | 1 | 4 | **DO NOT MERGE** | Comment deletion removed from the UI — admins lose all moderation ability while the backend sits unreachable. |
| [5](#pr-5--signup-form) | signup-form | 1 | 1 | 3 | **DO NOT MERGE** | `getUrlHistory()` returns `undefined` on empty sessionStorage — signup breaks for first-time visitors. |
| [6](#pr-6--member-welcome-emails) | welcome emails | 2 | 0 | 1 | **DO NOT MERGE** | Inverted scheduling guard means the job never registers; the feature this PR adds is dead on arrival — and it is masking a second bug that mass-emails imported members. |
| [7](#pr-7--kebab-case-file-renames) | file renames | 3 | 0 | 1 | **DO NOT MERGE** | Three `MODULE_NOT_FOUND` crashes from renames that were half-applied. Members API dies → no authentication. |
| [8](#pr-8--chinese-i18n) | zh i18n | 1 | 1 | 5 | **DO NOT MERGE** | `comments.json` deleted while `vite.config.mts` still requires it for every locale — comments-ui build fails. |
| [9](#pr-9--domain-warming-rounding) | DomainWarmingService | 1 | 2 | 2 | **DO NOT MERGE** | Test helper uses `Math.round`, implementation uses `Math.floor` — CI is red by construction. |
| [10](#pr-10--activitypub-bluesky-sharing) | ActivityPub / Bluesky | 0 | 3 | 3 | **DO NOT MERGE** | `strict: false` disables TypeScript strict checking for the entire activitypub app. |
| [11](#pr-11--shade-filter-component) | shade filters | 0 | 3 | 3 | **DO NOT MERGE** | Temp selection state is never cleared, so filter popovers show values carried over from a different field. |
| [12](#pr-12--tinybird-service) | TinybirdService | 2 | 2 | 1 | **DO NOT MERGE** | `jwt.verify()` replaced with `jwt.decode()` — signature validation removed outright. |
| [13](#pr-13--stats--tinybird-config) | stats config | 1 | 2 | 1 | **DO NOT MERGE** | Frontend builds `v2_api_kpis`, backend serves `api_kpis_v2`. Every versioned analytics call 404s. |

### The three worst findings in the set

1. **PR 12 — `jwt.verify()` → `jwt.decode()`.** The only finding in the entire audit that removes a security control. Signature validation is simply gone.
2. **PR 6 — `||` instead of `&&` on the welcome-email guard.** The only finding that can cause *irreversible external* harm: unsolicited bulk email to imported member lists. You cannot unsend email.
3. **PR 7 — three `MODULE_NOT_FOUND` crashes.** The only PR that cannot execute at all, and it takes member authentication down with it.

---

## Cross-cutting findings

These patterns span multiple PRs and matter more than any individual line comment.

**1. Two PRs edit the same file in contradictory directions.**
PR 3 and PR 9 both rewrite `DomainWarmingService.ts` — 8 of 63 findings land in that one file. PR 3 changes comparison operators at tier boundaries; PR 9 changes the rounding mode and day arithmetic. Merging either one invalidates the other's line numbers and, more importantly, its test expectations. **Sequence these two deliberately or you will merge a file nobody has reviewed in its combined state.** Neither review appears aware of the other.

**2. One bug is masking another, and fixing the first detonates the second.**
In PR 6, the scheduler guard is inverted (`hasScheduled.processOutbox` instead of `!hasScheduled.processOutbox`), so the outbox job never runs. That dead job is currently the only thing preventing the second bug — `||` instead of `&&` — from sending welcome emails to every member imported via CSV or created by an admin. A well-meaning engineer who fixes only the "obvious" scheduling bug ships a mass-mail incident. **These two must be fixed in the same commit.**

**3. Half-completed mechanical refactors are the single largest source of blockers.**
PR 7 (kebab-case renames) and PR 8 (i18n file rename) contribute 4 blockers between them, all from the same failure mode: a rename applied to the import site but not the file, or to the file but not the build config. These are exactly the changes reviewers wave through because the diff looks boring. **Any PR that renames files must be gated on a clean boot and a clean build, not on human reading.**

**4. Six findings have no file or line attached.**
PR 4, 8, 9, 11, 12, and 13 each contain one finding with `file_path: None`. These are the *structural* observations — removed UI affordances, build-config coupling, test/implementation drift — and they include some of the most severe issues in the set (PR 8's build break, PR 9's red CI). They are also the ones most likely to be lost in a line-anchored review UI, because they do not attach to a diff line. **Do not let review tooling bury these.**

**5. The style rules are drowning the substance.**
20 of 63 findings cite a named lint rule; 27 total are cosmetic. Semicolons (4), single quotes (3), `var` (2), yarn-vs-npm *in comments* (2), JSON indentation (2). None of these should occupy reviewer attention. **Push every one of them into ESLint/Prettier CI and delete them from the review surface.** The exception is PR 10's `strict: false`, which is filed as a style rule but is not one — see below.

**6. Two findings are filed as rule violations but are real engineering decisions.**
PR 10's `strict: false` is tagged "TypeScript Files Must Enable Strict Type Checking" as though it were formatting. It disables null-safety for an entire application. PR 8's `commentsFile.json` naming violation is tagged as a kebab-case nit, but it is the *same root cause* as that PR's build-breaking blocker. **Rule-tagging caused both to be under-weighted.**

---

## Per-PR detail

### PR 1 — boot sequence
`https://github.com/agentic-review-benchmarks/Ghost/pull/1` — 4 findings — **DO NOT MERGE**

> **Most critical:** Ghost does not boot. `scheduling.init()` is called without the `apiUrl` argument its constructor requires, and `PostScheduler` throws `IncorrectUsageError` on a missing value. This is a hard crash in the startup path, not a degraded feature.

**BLOCKER (1)**
- **`scheduling.init()` missing required `apiUrl`** — `ghost/core/core/boot.js:368`. The previous call passed `urlUtils.urlFor('api', {type: 'admin'}, true)`. `PostScheduler` explicitly validates this parameter and throws. The process dies during boot. `apiUrl` is also what signs admin tokens and builds publish callback URLs, so even if the throw were removed, scheduled publishing could not work. Restore the argument.

**REQUIRED (2)**
- **Slack integration silently dead** — `boot.js:351-377`. `slack.listen()` was dropped from the `Promise.all` block while the module import was left in place. The `post.published` and `slack.test` handlers are never registered. Nothing errors; Slack notifications just never fire, and the leftover import makes the code read as though the feature is wired up. Sites with a correctly configured Slack webhook will report this as a support bug, not a deploy regression. Re-add `slack.listen()`.
- **Email service init order violated** — `boot.js:349-366`. `emailAddressService.init()` was moved out of sequential execution into the parallel block alongside `emailService.init()`. The comment directly above still reads *"newsletter service and email service depend on email address service"* — the code now contradicts the comment three lines below it. `EmailServiceWrapper.init()` consumes `emailAddressService` and may observe it mid-initialization. This is a genuine race: it will pass locally, pass in CI, and fail intermittently in production with a null reference or a silently wrong email configuration. Restore the sequential await.

**SUGGESTION (1)**
- **npm referenced in a comment** — `boot.js:313`. `// NOTE: If you need to add dependencies for services, use npm install <package>`. The repo mandates yarn v1. It is a comment; fix it in passing, do not spend review cycles on it.

---

### PR 2 — comments-ui reply forms
`https://github.com/agentic-review-benchmarks/Ghost/pull/2` — 4 findings — **DO NOT MERGE**

> **Most critical:** Reply threading persists the wrong parent. `submit()` sends `parent.id` as `in_reply_to_id` instead of `openForm.in_reply_to_id`. For nested replies those differ, so every multi-level reply is recorded against the top-level comment. This writes incorrect relational data to the database — it is not a rendering bug, and it does not fix itself when you deploy a patch. Every reply created while this is live needs a backfill you have no clean signal to reconstruct.

**BLOCKER (2)**
- **Wrong `in_reply_to_id` corrupts threading** — `reply-form.tsx:24-35`. See above. Silent, persisted, and retroactively unfixable. This is worse than a crash precisely because nothing alerts on it.
- **Missing optional chaining crashes the form** — `form.tsx:311-315`. `openForm.in_reply_to_snippet` without the `?.` the original code had. `openForm` is legitimately `undefined` when rendering the main (non-reply) comment form, which is the most common render path there is. `Cannot read property 'in_reply_to_snippet' of undefined` takes the component down. Restore `openForm?.in_reply_to_snippet`.

**REQUIRED (1)**
- **Editor gated on `expertise` instead of name** — `form.tsx:258-265`. Editability checks `member?.expertise` where it should check `memberName` (from `member?.name`). Expertise is optional metadata; name is the actual posting requirement. Result: any member who never filled in an expertise field cannot type in the comment box at all, despite being fully entitled to comment. The surrounding comment still describes the name-based logic. High user impact, trivially fixed, and it will look like a total product outage to affected members.

**SUGGESTION (1)**
- **Tailwind class ordering** — `reply-form.tsx:47`. `pr-2` before `mt-[-16px]`; convention wants margin before padding. Formatter territory.

---

### PR 3 — domain warming thresholds
`https://github.com/agentic-review-benchmarks/Ghost/pull/3` — 4 findings — **DO NOT MERGE**

> **Most critical:** There is no single catastrophic line here — there are three separate comparison-operator bugs in one rate-limiting function, and collectively they mean the documented warmup table is wrong at every boundary. This function decides how much email leaves your domain. Getting it wrong in the permissive direction damages sender reputation, which is slow and expensive to repair.

No blockers: nothing crashes, and nothing is a security or build failure. That does **not** make this mergeable. Three correctness defects in one small function is a review failure, not a nit pile.

**REQUIRED (3)**
- **Date filter includes today** — `DomainWarmingService.ts:101-105`. `#getHighestCount()` filters on `created_at:<=`, including the current day, while its own docstring says today must be excluded. Early in the day the method returns a *partial* count, so the computed limit regresses below yesterday's. The warmup ratchets backwards at unpredictable times of day. Use a strict `<`.
- **`>=` at the 400k high-volume boundary** — `:124-129`. At exactly 400,000 the code applies the high-volume cap (1.2× / +75k) instead of the documented 2× tier. A site at precisely 400k gets 480k instead of 800k — a 40% haircut at the exact milestone where throughput matters most. Should be `>`.
- **`<` skips every threshold tier** — `:131-135`. Exact boundary values (1000, 5000, 100000, 400000) fall through to the next factor. 1000 → 1.5× (1500) instead of 1.25× (1250); 5000 → 1.75× instead of 1.5×; 100000 → 2× instead of 1.75×. Note the direction: this one is *permissive*, so it over-sends at boundaries. Should be `<=`.

**SUGGESTION (1)**
- **`!=` instead of `!==`** — `:111-112`. Null check on `count`. Repo mandates strict equality. Lint rule.

> **Coordinate with PR 9.** Both PRs rewrite this file. Merging them independently produces a combined state neither review covered.

---

### PR 4 — admin comments list
`https://github.com/agentic-review-benchmarks/Ghost/pull/4` — 6 findings — **DO NOT MERGE**

> **Most critical:** Comment deletion is gone from the UI. The dropdown item that called `setCommentToDelete` was removed, while `AlertDialog`, `confirmDelete`, the `deleteComment` mutation, and `commentToDelete` state all remain — fully built, completely unreachable. Administrators cannot remove spam, abuse, or unlawful content through the product. For a comments feature that is a moderation and compliance failure, not a missing button.

**BLOCKER (1)**
- **Delete comment removed from UI** — no file attribution in the source data. See above. The intact backend makes this *more* dangerous, not less: the code reviews as complete, and the capability loss is only visible by using the product.

**REQUIRED (1)**
- **`useEffect` missing `item.html` dependency** — `comments-list.tsx:92-104`. Empty dependency array, but the effect reads `item.html` to decide whether to clamp. Edited or refetched comments keep stale clamp state, so "Show more" appears when there is nothing more, or hides genuinely truncated content. Add `item.html` to the deps.

**SUGGESTION (4)**
- **Missing semicolons** — `:88-90` and `:84-88`. Two separate findings over overlapping line ranges — effectively **one duplicate finding double-counted**. Prettier.
- **`onAddFilter` null check removed** — `:236-248`. The finding is weak. `onAddFilter` is a *required* prop in the TypeScript signature; the runtime guard was redundant with the type. The finding's own wording hedges — "if `onAddFilter` is ever undefined." Restore the guard only if untyped JS callers exist. Not worth blocking on.
- **Ternary → `&&` for feature image** — `:350-358`. **This finding is wrong.** React does not render `''` as a visible DOM node or emit a warning for it; `{'' && <img/>}` renders nothing, exactly like the ternary. There is no behavioral difference to fix. Dismiss it.

---

### PR 5 — signup form
`https://github.com/agentic-review-benchmarks/Ghost/pull/5` — 5 findings — **DO NOT MERGE**

> **Most critical:** `getUrlHistory()` can now return `undefined`, violating its `URLHistory` return type, and `sendMagicLink()` then treats it as an array. The trigger is an empty or invalid `sessionStorage` on a same-host embed — which is the definition of a **first-time visitor**. This is not an edge case; it is the primary acquisition path.

**BLOCKER (1)**
- **`getUrlHistory()` returns `undefined`** — `helpers.tsx:40-46`. The original guarded with `if (history)` before returning, falling back to a constructed array. That guard is gone. Empty sessionStorage → `undefined` → runtime error in `sendMagicLink()` → signup fails for new visitors on same-host embeds. Restore the fallback.

**REQUIRED (1)**
- **Loading state never reset in minimal mode** — `form-page.tsx:27-30`. On a *successful* magic-link send in minimal mode, `setLoading(true)` is never paired with `setLoading(false)` — the removed call. The non-minimal path recovers incidentally via `setPage()`. The user's signup actually succeeded, but the button spins forever and they cannot resubmit; most will assume it failed. Add the `setLoading(false)`.

**SUGGESTION (3)**
- **Email trimmed on submit but validated/displayed untrimmed** — `form-view.tsx:54-56`. Filed as a functional bug; it is close to cosmetic. `' user@example.com '` passes the untrimmed regex and the API correctly receives the trimmed value, so the *outcome is right*. Only the echoed display can disagree. Tidy it by trimming before validation, but it does not gate ship.
- **Double quotes on `STORAGE_KEY`** — `helpers.tsx:20`. Lint.
- **Double quotes in import specifier** — `.storybook/preview.tsx:4`. Lint, and in a Storybook config file at that.

---

### PR 6 — member welcome emails
`https://github.com/agentic-review-benchmarks/Ghost/pull/6` — 3 findings — **DO NOT MERGE**

> **Most critical:** Read both blockers together — individually they are bad, and in sequence they are an incident. The scheduling guard is inverted, so the outbox job never registers and the feature this PR exists to deliver does nothing. That dead job is also the only thing currently suppressing the second bug, which sends welcome emails to members created by import or by an admin. **Fix the scheduler alone and you mass-mail every imported member on the site.**

**BLOCKER (2)**
- **Job never scheduled** — `member-welcome-emails/jobs/index.js:15`. The condition is `hasScheduled.processOutbox && !process.env.NODE_ENV.startsWith('test')` — it requires the job to already be scheduled in order to schedule it. `hasScheduled.processOutbox` initialises to `false`, so the branch is unreachable forever. Must be `!hasScheduled.processOutbox`. The entire welcome-email pipeline is inert.
  *Auditor's note, not in the source findings:* `process.env.NODE_ENV.startsWith(...)` will itself throw `TypeError` if `NODE_ENV` is unset, which is legal in a bare production container. Guard it while you are in there.
- **`||` instead of `&&` on the send guard** — `MemberRepository.js:342`. Welcome emails fire if the config is set **or** the source is `'member'`, rather than requiring both. Two consequences: emails go out while the feature is switched off, and they go out for disallowed sources such as `import` and `admin`. A CSV import of an existing member list becomes an unsolicited bulk send — spam complaints, blocklisting, and durable damage to sending reputation. Irreversible; there is no recall. Must be `&&`.

**SUGGESTION (1)**
- **`var` instead of `let`/`const`** — `MemberRepository.js:340`. Lint. Note it sits two lines from the mass-mail bug and was raised with comparable prominence.

---

### PR 7 — kebab-case file renames
`https://github.com/agentic-review-benchmarks/Ghost/pull/7` — 4 findings — **DO NOT MERGE**

> **Most critical:** This PR does not run. Three `require()` paths point at filenames that do not exist, each throwing `MODULE_NOT_FOUND`. The worst is `magic-link` — it takes down members API initialisation, and with it member authentication, signup, and magic links across the entire application. A mechanical rename was applied to import sites and files inconsistently in both directions.

**BLOCKER (3)**
- **`magic-link` path wrong** — `members-api.js:18-19`. Requires `'./../../lib/magic-link/magic-link'`; the file is still `MagicLink.js`. Members API fails to initialise → no authentication, no signup, no magic links. Correct path: `./../../lib/magic-link/MagicLink`.
- **`DonationBookshelfRepository` path wrong** — `donation-service-wrapper.js:10-11`. Opposite direction: the file *was* renamed to `donation-bookshelf-repository.js`, the require still says `./DonationBookshelfRepository`. Donation service init throws; payment tracking and storage break.
- **`email-event-storage` / `email-event-processor` paths wrong** — `email-analytics-service-wrapper.js:11-13`. Requires kebab-case; files remain `EmailEventStorage.js` and `EmailEventProcessor.js`. Email analytics initialisation throws — no open, click, or bounce tracking.

The inconsistency runs both ways, which rules out a single missed `git mv`. Regenerate the rename mechanically and verify with a boot smoke test. **A PR of this shape should never be reviewed by reading; it should be gated on the app starting.**

**SUGGESTION (1)**
- **Missing semicolons in requires** — `members-api.js:1-10`. Lint.

---

### PR 8 — Chinese i18n
`https://github.com/agentic-review-benchmarks/Ghost/pull/8` — 7 findings — **DO NOT MERGE**

> **Most critical:** `ghost/i18n/locales/zh/comments.json` was deleted, but `apps/comments-ui/vite.config.mts:56` still lists `comments.json` in `dynamicRequireTargets` for every entry in `SUPPORTED_LOCALES`, `zh` included. The comments-ui build fails outright, or ships and fails at runtime for Chinese readers.

**BLOCKER (1)**
- **`comments.json` deleted while still required by the build** — no file attribution in the source data. See above. Either restore `comments.json` or update `vite.config.mts` in the same PR — the two are coupled and cannot land separately.

**REQUIRED (1)**
- **Missing `{newsletterName}` interpolation** — `portal.json:6-9`. Source string is `'{memberEmail} will no longer receive {newsletterName} newsletter.'`; the translation renders only `'{memberEmail}将不会再收到新闻信。'`. A member unsubscribing from one of several newsletters is never told which one. That is a real risk of unintended unsubscribes, and dropping an interpolation variable will also trip i18n parity checks.

**SUGGESTION (5)**
- **`commentsFile.json` uses camelCase** — `:1`. Filed as a naming-convention nit. It is **the same root cause as the blocker above** — `comments.json` was renamed to `commentsFile.json`. The rule tag caused it to be triaged as cosmetic. The naming fix and the build fix are one change.
- **`Name` translated inconsistently across namespaces** — `portal.json:114-117`. `名字` in `ghost.json` vs `名称` in `portal.json`, where `姓名` was intended. Real translation-quality issue, zero functional impact.
- **`Enter your name` placeholder inconsistency** — `portal.json:68-72`. `输入您的名字` (first name) against a `姓名` (full name) label. Same category.
- **4-space indentation in JSON** — `ghost.json:6` and `portal.json:9`. Two findings, one rule. Formatter.

---

### PR 9 — domain warming rounding
`https://github.com/agentic-review-benchmarks/Ghost/pull/9` — 5 findings — **DO NOT MERGE**

> **Most critical:** CI cannot pass. The integration test helper `getExpectedLimit` computes with `Math.round` while the implementation uses `Math.floor`. On day 1 the formula yields 237.6 → implementation 237, test expects 238. The suite is red by construction, independent of whether the implementation is right.

**BLOCKER (1)**
- **Test/implementation rounding mismatch** — no file attribution in the source data. See above. Decide which rounding mode is correct and make both sides agree. Until then nothing here is mergeable regardless of the other findings.

**REQUIRED (2)**
- **`Math.ceil` in `getDaysSinceFirstEmail`** — `:75`. Should be `Math.floor`. Any partial day rounds up, so the very first email lands on "day 1" instead of "day 0" and the whole 42-day ramp shifts forward. Every day of the warmup then applies a limit intended for the following day — the schedule runs permissively, which is the dangerous direction for sender reputation.
- **`>` instead of `>=` on the completion check** — `:85-86`. With `totalDays = 42`, warmup does not complete until day 43. Day 42 still applies a computed limit rather than returning `Infinity`. One extra throttled day, and it contradicts the documented 42-day period. Low impact, unambiguous fix.

**SUGGESTION (2)**
- **`Math.floor` instead of `Math.round` on the limit** — `:89-95`. Filed as a defect; it is a **defensible engineering choice**. Flooring a rate limit is the conservative, standard behaviour — you do not round a cap upward. The finding's "accumulates significant deviation" framing overstates a sub-1-message-per-day difference. The only thing that genuinely must be resolved is the *disagreement with the test*, already captured as the blocker above. Do not "fix" the implementation to match a test that may itself be wrong.
- **Missing semicolons in `getWarmupLimit`** — `:83-98`. Lint.

> **Coordinate with PR 3.** Same file, 8 findings between them, and PR 3's boundary changes will move the very line numbers PR 9's tests assert against.

---

### PR 10 — ActivityPub Bluesky sharing
`https://github.com/agentic-review-benchmarks/Ghost/pull/10` — 6 findings — **DO NOT MERGE**

> **Most critical:** `strict: false` in `apps/activitypub/tsconfig.json`. This is filed under a style rule and it is not a style issue — it switches off `strictNullChecks` and the rest of the strict family for an entire application. Every null-safety guarantee in that codebase silently evaporates, and the blast radius is unbounded relative to this PR's diff. Nothing else in this PR justifies it.

No individual finding here crashes, breaks the build, or touches security, so nothing meets the blocker bar — but `strict: false` comes closest, and it should be treated as non-negotiable.

**REQUIRED (3)**
- **`strict: false` in tsconfig** — `apps/activitypub/tsconfig.json:18`. See above. Revert to `true` and fix whatever type errors that surfaces; if that is too large for this PR, it is too large to bury in this PR.
- **`handleEnable` lost its try/catch** — `BlueskySharing.tsx:48-55`. Any failure of `enableBlueskyMutation` — network blip, 500, timeout — leaves loading pinned `true` with no path to retry short of a page refresh. `handleDisable` still handles errors correctly, so the two halves of the same feature now behave differently. Restore the try/catch.
- **Missing `accountFollows` invalidation** — `use-activity-pub-queries.ts:2820-2834`. `confirmBlueskyHandle` updates the account cache but never invalidates `QUERY_KEYS.accountFollows('index', 'following')`. Both `enableBluesky` and `disableBluesky` do. Enabling Bluesky auto-follows `brid.gy`, so after confirmation the follow is invisible until manual refresh, and a brand-new integration reads as half-broken on first use.

**SUGGESTION (3)**
- **Polling off-by-one** — `:103-117`. 13 requests instead of `MAX_CONFIRMATION_RETRIES = 12`; one wasted call and a 5-second-late timeout message. Correct, trivial, not worth argument.
- **Missing semicolon on `BlueskyDetails` type alias** — `:2722-2732`. Lint.
- **Double quotes in JSX attributes** — `BlueskySharing.tsx:176`. Lint.

---

### PR 11 — shade filter component
`https://github.com/agentic-review-benchmarks/Ghost/pull/11` — 6 findings — **DO NOT MERGE**

> **Most critical:** `setTempSelectedValues([])` was removed from the `onClose` handler, so temporary selections survive the popover closing. Open a field, start picking values, close without confirming, then open a *different* field — the previous field's values are pre-selected. Users apply filters they never chose and read analytics that do not answer the question they asked. Silent wrong output beats a visible error every time for how much damage it does.

No blockers: nothing crashes, no security or build impact. Three concurrent state-management defects in one component still make this unshippable.

**REQUIRED (3)**
- **Temp selected values not cleared on close** — `filters.tsx:2098-2101`. See above. Restore the cleanup call. *Terminology:* the finding calls this a "memory leak." **It is not** — it is cross-interaction state pollution. Nothing grows unboundedly. The mislabel matters because it invites a reader to dismiss this as a perf nit when the actual symptom is wrong data on screen.
- **`autoCloseOnSelect` is a no-op in non-inline multiselect** — no file attribution; described at lines 1135-1137. The non-inline path calls only `onClose?.()` and never `setOpen(false)`. `SelectOptionsPopover` can be constructed without an `onClose` prop (line 1598), so optional chaining silently does nothing and the popover stays open. The inline path at 1272-1273 calls `handleClose()` and does both. Route both paths through `handleClose()`.
- **Single-select never calls `handleClose()`** — `:1275-1278`. Calls `setOpen(false)` directly, skipping the search-input reset and the `onClose` callback that the multiselect path performs. Next open shows the previous interaction's search text and filtered list. Same root cause as above: three code paths that should share one close routine and do not.

**SUGGESTION (3)**
- **Search input cleared synchronously** — `:1049-1053`. The removed 200ms `setTimeout` existed to let the close animation finish; clearing immediately flashes the unfiltered list mid-animation. Purely cosmetic, and the debounce-for-animation pattern is fragile anyway. Fix when convenient.
- **`var newValues`** — `:1123-1133`. Lint.
- **Double-quoted `className`** — `:943`. Lint.

---

### PR 12 — Tinybird service
`https://github.com/agentic-review-benchmarks/Ghost/pull/12` — 5 findings — **DO NOT MERGE**

> **Most critical:** `_isJWTExpired` now calls `jwt.decode()` where it called `jwt.verify()`. `decode()` performs no cryptographic validation whatsoever — it parses the payload and returns it. The signature check is gone. This is the only finding in the entire 63 that removes a security control, and there is no version of "we'll fix it in a follow-up" that applies.

**BLOCKER (2)**
- **`jwt.verify()` → `jwt.decode()`** — `TinybirdService.js:162-170`. Revert unconditionally. *Honest scoping, because overstating this helps nobody:* the token being checked here is one the server generated itself, so the immediate exploit path depends on whether any externally-supplied token reaches this method. That caveat affects the CVE writeup, **not** the remediation. Signature verification is load-bearing precisely because the trust boundary moves without warning, and a future refactor that routes a client token through this path would inherit a silent auth bypass. Restore `jwt.verify()`.
- **Token cache stores the whole object** — `:97-99`. `getToken` caches `tokenData` (`{token, exp}`) rather than `tokenData.token`, producing `{token: {token: string, exp: number}, exp: number}`. Every consumer expecting a string — the `/api/tinybird/token` endpoint, `stats/tinybird.js` — receives an object and fails to authenticate against Tinybird. Complete functional break of the integration.

**REQUIRED (2)**
- **`_isJWTExpired` receives an object** — no file attribution; consequence of the caching change at line 98, called at line 96. `jwt.decode()` gets an object instead of a JWT string, fails, and the method returns `true` forever. Tokens are regenerated on every single request and the cache never serves a hit. Same root cause as the blocker above; fixing the cache to store `tokenData.token` resolves both. Verify together.
- **`noTimestamp: true` removed** — `:147`. Tokens now carry an `iat` claim they previously omitted. The finding is **speculative** — it says the change "may cause authentication failures if Tinybird validates payload structure," with no evidence that it does. Either confirm against Tinybird's actual requirements or restore the option because nothing in this PR needed it changed. Do not merge an unexplained change to a token's wire format on a hunch either way.

**SUGGESTION (1)**
- **npm referenced in documentation comments** — `:61-67`. Repo mandates yarn. Comment text.

---

### PR 13 — stats / Tinybird config
`https://github.com/agentic-review-benchmarks/Ghost/pull/13` — 4 findings — **DO NOT MERGE**

> **Most critical:** The frontend and backend disagree on endpoint naming. `stats-config.ts` builds `${config.version}_${endpointName}` → `v2_api_kpis`, while the backend serves `api_kpis_v2`. The comment directly above the line even documents the correct `api_kpis_v2` pattern — the implementation inverts what its own comment says. Whenever a version is configured, every analytics call hits a URL that does not exist.

**BLOCKER (1)**
- **Version prefix/suffix inverted** — `stats-config.ts:17-18`. See above. Guaranteed 404s and empty analytics in exactly the configuration this PR exists to support. Build the suffix as `${endpointName}_${config.version}`.

**REQUIRED (2)**
- **`source` parameter dropped from the Tinybird request** — `ContentStatsService.js:100-105`. `fetchRawTopContentData` still validates `options.source` — including the empty-string case for Direct traffic — but no longer assigns it to `tinybirdOptions.source`. The call goes out unfiltered and returns **unfiltered results that the UI presents as filtered**. This is the most insidious finding in the PR: the 404s above are loud and obvious, whereas this quietly shows users the wrong numbers with no error anywhere. It is filed below the blocker only because the data is displayed, not persisted.
- **Version suffix now applied in local dev** — no file attribution. The `!localEnabled` guard was removed, so versioning applies even against local Tinybird instances, which typically expose only base endpoints (`api_kpis`, not `api_kpis_v2`). Local development 404s. The PR also deletes the test `'ignores tbVersion when local is enabled'` that documented this exact contract — **deleting the test that would have caught the change is the part to push back on**, not just the behaviour.

**SUGGESTION (1)**
- **JSX prop ordering** — `framework-provider.tsx:90`. `children` before `value` on `FrameworkContext.Provider`; convention wants regular props first. Lint.

---

## Recommended remediation order

Sequenced by blast radius and by dependency between PRs, not by PR number.

1. **PR 12** — restore `jwt.verify()`. Security control, no acceptable delay.
2. **PR 6** — fix the scheduler guard **and** the `||`→`&&` guard in one commit. Never the first alone.
3. **PR 7** — regenerate the renames; gate on a boot smoke test.
4. **PR 1** — restore the `apiUrl` argument; Ghost must boot.
5. **PR 8** — resolve `comments.json` against `vite.config.mts`; unbreak the build.
6. **PR 2** — fix `in_reply_to_id` before any of this reaches production and starts writing bad rows.
7. **PR 5, 13, 4** — user-facing breakage: signup, analytics, moderation.
8. **PR 3 + PR 9 together** — single combined review of `DomainWarmingService.ts`; settle the rounding contract before touching either.
9. **PR 10, 11** — restore `strict: true`, then the state-management fixes.
10. **All 27 suggestions** — move to ESLint/Prettier CI. Do not spend another review cycle on quote characters.

---

## Method, provenance, and limitations

**Read this section before quoting any number above.**

- **Provenance.** Every finding is taken from `github-pull-request-review-comments.jsonl`, filtered to `repo == "Ghost"` (13 of 100 records; the other 87 cover cal.com, dify, firefox-ios, prefect, tauri, aspnetcore, and redis and are out of scope). Titles, descriptions, file paths, and line numbers are as recorded in the source.
- **Severity is this audit's judgment, not the source data's.** The JSONL carries no severity field. Every BLOCKER / REQUIRED / SUGGESTION assignment here was applied against the rubric at the top of this document and is arguable at the margins — particularly PR 3 and PR 11, which have no blocker but are still unmergeable, and PR 13's dropped `source` parameter, which sits at the REQUIRED/BLOCKER boundary.
- **Findings were not verified against the Ghost source tree.** This is a triage of the review comments, not an independent re-review of the diffs. Where a finding looked wrong or overstated on its face it is called out as such — PR 4's `&&` vs ternary claim (dismissed as incorrect), PR 4's duplicate semicolon findings, PR 9's `Math.floor` (defensible as written), PR 12's `noTimestamp` (unevidenced), PR 4's `onAddFilter` guard (redundant with the type system). **Before acting on any single finding, confirm it against the actual diff.**
- **`num_of_issues` matched the length of `issues` in all 13 records.** No records were dropped or truncated.
- **Six findings carry `file_path: None`** and could not be line-attributed: PR 4, 8, 9, 11, 12, 13. Two of them are blockers.
- **Absence of a finding is not evidence of correctness.** This audit can only triage what the reviewers wrote down. A PR with three findings has not been shown to contain only three defects.
