#!/usr/bin/env bash
#
# setup-hooks.sh - Wire up Husky git hooks for the Ghost monorepo.
#
# The hooks installed here enforce, at commit/push time, the checks that
# already gate PRs in .github/workflows/ci.yml, plus the rule violations that
# recur most often in our PR reviews.
#
#   Recurring review violations -> pre-commit check
#     Code Must Always Use Semicolons ............... eslint (semi)
#     Code Must Use Single Quotes for Strings ....... eslint (quotes)
#     Code Must Use let or const Instead of var ..... eslint (no-var)
#     Code Must Use Strict Equality Operators ....... eslint (eqeqeq)
#     React Components Must Sort JSX Props .......... eslint (react/jsx-sort-props)
#     Package Manager Must Be Yarn v1 ............... yarn-only guard
#     i18n Files Must Use Kebab-Case Naming ......... i18n filename guard
#     Code Must Use 4-Space Indentation (locales) ... i18n JSON indent guard
#     TypeScript Files Must Enable Strict Checking .. tsconfig strict guard
#
#   CI command (.github/workflows/ci.yml) -> pre-push check
#     yarn nx affected -t lint      (line 249) ...... same command, local base
#     yarn nx run-many -t build:tsc (line 427) ...... same command
#     yarn nx affected -t test:unit (line 480) ...... same command, local base
#
# Usage:  ./setup-hooks.sh [--force]
#
set -euo pipefail

FORCE=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
grey='\033[0;90m'
no_color='\033[0m'

info() { echo -e "${grey}$*${no_color}"; }
ok() { echo -e "${green}✔${no_color} $*"; }
warn() { echo -e "${yellow}!${no_color} $*"; }
fail() { echo -e "${red}✖${no_color} $*" >&2; exit 1; }

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not inside a git repository."

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

[ -f package.json ] || fail "No package.json at repository root ($ROOT)."
grep -q '"name": "ghost-monorepo"' package.json \
    || fail "This does not look like the Ghost monorepo (expected \"name\": \"ghost-monorepo\")."

command -v node >/dev/null 2>&1 || fail "node is not installed."
command -v yarn >/dev/null 2>&1 || fail "yarn is not installed. Ghost uses yarn v1; see AGENTS.md."

# Ghost points husky at .github/hooks via the root "prepare" script. Honour
# whatever that script says so this stays correct if the directory ever moves.
HOOKS_DIR="$(node -e '
const {execSync} = require("child_process");
const prepare = (require("./package.json").scripts || {}).prepare || "";
const match = prepare.match(/husky\s+install\s+(\S+)/);
process.stdout.write(match ? match[1] : ".husky");
')"

info "Repository root : $ROOT"
info "Hooks directory : $HOOKS_DIR"

if [ ! -d node_modules ]; then
    warn "node_modules is missing - run 'yarn' before committing, or the hooks will fail."
fi

# --------------------------------------------------------------------------
# Install husky and point core.hooksPath at the hooks directory
# --------------------------------------------------------------------------

mkdir -p "$HOOKS_DIR"

if [ -x node_modules/.bin/husky ]; then
    node_modules/.bin/husky install "$HOOKS_DIR" >/dev/null
    ok "husky installed (core.hooksPath -> $HOOKS_DIR)"
else
    # No husky binary yet (fresh checkout without a yarn install). Setting
    # core.hooksPath directly gives working hooks now; 'yarn' will later run
    # the prepare script and converge on the same value.
    git config core.hooksPath "$HOOKS_DIR"
    warn "husky binary not found - set core.hooksPath directly. Run 'yarn' to finish setup."
fi

backup_existing() {
    local target="$1"
    [ -e "$target" ] || return 0
    if [ "$FORCE" = false ]; then
        local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$target" "$backup"
        info "  backed up $(basename "$target") -> $(basename "$backup")"
    fi
}

write_file() {
    local target="$1"
    backup_existing "$target"
    cat >"$target"
    chmod +x "$target"
}

# --------------------------------------------------------------------------
# lint-staged config
#
# Kept out of package.json so running this script leaves no tracked file
# dirty. Only covers workspaces that use eslintrc: apps/admin and e2e use
# flat config, which eslint 8 cannot load in the same run, so their files are
# skipped here and covered by the pre-push 'nx affected -t lint' instead.
#
# The repo's own package.json config only matched "*.js", which is why the
# .ts/.tsx violations in review kept slipping through.
# --------------------------------------------------------------------------

LINT_STAGED_CONFIG="$HOOKS_DIR/lint-staged.config.js"
backup_existing "$LINT_STAGED_CONFIG"
cat >"$LINT_STAGED_CONFIG" <<'LINTSTAGED'
const {existsSync} = require('fs');
const {dirname, join, resolve, relative, sep} = require('path');

const root = resolve(__dirname, '..', '..');

const ESLINTRC_NAMES = [
    '.eslintrc.js',
    '.eslintrc.cjs',
    '.eslintrc.json',
    '.eslintrc.yml',
    '.eslintrc.yaml',
    '.eslintrc'
];

// eslint 8 resolves eslintrc by walking up from the linted file. A file with
// no eslintrc ancestor makes the whole run exit non-zero with "No ESLint
// configuration found", so filter those out rather than block the commit.
function hasEslintrc(file) {
    let dir = dirname(resolve(root, file));

    while (dir.startsWith(root)) {
        if (ESLINTRC_NAMES.some(name => existsSync(join(dir, name)))) {
            return true;
        }

        if (dir === root) {
            return false;
        }

        dir = dirname(dir);
    }

    return false;
}

function isFlatConfigWorkspace(file) {
    const rel = relative(root, resolve(root, file));
    return rel.startsWith(`apps${sep}admin${sep}`) || rel.startsWith(`e2e${sep}`);
}

function shellQuote(value) {
    return `'${value.replace(/'/g, `'\\''`)}'`;
}

module.exports = {
    '*.{js,jsx,cjs,mjs,ts,tsx}': (files) => {
        const lintable = files
            .filter(file => !isFlatConfigWorkspace(file))
            .filter(hasEslintrc);

        if (!lintable.length) {
            return [];
        }

        return [`eslint --max-warnings=0 ${lintable.map(shellQuote).join(' ')}`];
    }
};
LINTSTAGED
ok "wrote $LINT_STAGED_CONFIG"

# --------------------------------------------------------------------------
# Shared check library
# --------------------------------------------------------------------------

write_file "$HOOKS_DIR/ghost-checks.sh" <<'CHECKS'
#!/usr/bin/env bash
# Shared helpers for the Ghost git hooks. Sourced, never executed directly.

hook_red='\033[0;31m'
hook_green='\033[0;32m'
hook_yellow='\033[1;33m'
hook_grey='\033[0;90m'
hook_no_color='\033[0m'

hook_step() { echo -e "${hook_grey}› $*${hook_no_color}"; }
hook_pass() { echo -e "${hook_green}✔${hook_no_color} $*"; }
hook_warn() { echo -e "${hook_yellow}!${hook_no_color} $*"; }
hook_fail() { echo -e "${hook_red}✖ $*${hook_no_color}" >&2; }

# Hooks are a developer convenience; CI is the real gate. Skip in CI, and give
# people a documented escape hatch that is easier to remember than --no-verify.
hook_should_skip() {
    [ -n "${CI:-}" ] || [ "${HUSKY:-}" = "0" ] || [ -n "${SKIP_HOOKS:-}" ]
}

# Staged files, NUL-separated. Excludes deletions so checks never run against
# a path that no longer exists.
hook_staged_files() {
    git diff --cached --name-only --diff-filter=ACMR -z
}

# Lines added by this commit for a given path, without the leading '+'.
hook_added_lines() {
    git diff --cached -U0 -- "$1" | sed -n 's/^+\([^+].*\)/\1/p;s/^+$//p'
}
CHECKS
ok "wrote $HOOKS_DIR/ghost-checks.sh"

# --------------------------------------------------------------------------
# pre-commit
# --------------------------------------------------------------------------

write_file "$HOOKS_DIR/pre-commit" <<'PRECOMMIT'
#!/usr/bin/env bash
#
# Fast, staged-files-only checks. Mirrors the eslint gate from
# .github/workflows/ci.yml (yarn nx affected -t lint) and the rule violations
# that recur most in PR review.
#
# Bypass with SKIP_HOOKS=1 git commit  (or git commit --no-verify)
#
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname -- "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/ghost-checks.sh"

hook_should_skip && exit 0
cd "$ROOT" || exit 1

status=0

##
## 1) Unstage modified submodules
##    Preserved from the previous hook: submodule pointer bumps should never
##    ride along with an unrelated change.
##
if [ -f .gitmodules ]; then
    SUBMODULES=$(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')

    if [ -n "$SUBMODULES" ]; then
        MOD_SUBMODULES=$(git diff --cached --name-only --ignore-submodules=none | grep -Fx "$SUBMODULES")

        if [ -n "$MOD_SUBMODULES" ]; then
            hook_step "Removing submodules from commit"

            for SUB in $MOD_SUBMODULES; do
                git reset --quiet HEAD "$SUB"
                echo -e "  ${hook_grey}unstaged: $SUB${hook_no_color}"
            done

            if output=$(git diff --cached --name-only) && [ -z "$output" ]; then
                hook_fail "Nothing left to commit after removing submodules."
                exit 1
            fi
        fi
    fi
fi

mapfile -d '' -t STAGED < <(hook_staged_files)

if [ ${#STAGED[@]} -eq 0 ]; then
    exit 0
fi

##
## 2) eslint on staged files, warnings treated as errors
##    Covers: semicolons, single quotes, no-var, strict equality, indentation,
##    JSX prop ordering.
##
hook_step "Linting staged files"

if [ -x node_modules/.bin/lint-staged ]; then
    if ! node_modules/.bin/lint-staged --relative --config "$HOOKS_DIR/lint-staged.config.js"; then
        hook_fail "eslint failed. Fix the reported problems, or run 'yarn eslint --fix <file>'."
        status=1
    else
        hook_pass "eslint clean"
    fi
else
    hook_warn "lint-staged not installed - skipping lint. Run 'yarn' to enable it."
fi

##
## 3) Yarn v1 only  (AGENTS.md: "Always use yarn (v1) for all commands")
##
NPM_OFFENDERS=""

for file in "${STAGED[@]}"; do
    case "$file" in
        */package-lock.json|package-lock.json)
            hook_fail "package-lock.json is staged. Ghost uses yarn v1 - delete it and commit yarn.lock instead."
            status=1
            continue
            ;;
        *.js|*.jsx|*.cjs|*.mjs|*.ts|*.tsx|*.md|*.json|*.yml|*.yaml|*.sh)
            ;;
        *)
            continue
            ;;
    esac

    while IFS= read -r line; do
        case "$line" in
            *ghost-hooks:allow-npm*) continue ;;
        esac

        if echo "$line" | grep -qE '(^|[^a-zA-Z0-9_.-])(npm[[:space:]]+(install|i|ci|run|add)([[:space:]]|$)|npx[[:space:]])'; then
            NPM_OFFENDERS="${NPM_OFFENDERS}  ${file}: $(echo "$line" | sed 's/^[[:space:]]*//')"$'\n'
        fi
    done < <(hook_added_lines "$file")
done

if [ -n "$NPM_OFFENDERS" ]; then
    hook_fail "Ghost uses yarn v1, but these added lines call npm/npx:"
    printf '%s' "$NPM_OFFENDERS" >&2
    echo -e "${hook_grey}  Use the yarn equivalent, or append 'ghost-hooks:allow-npm' to the line if npm is genuinely required.${hook_no_color}" >&2
    status=1
fi

##
## 4) i18n locale files: kebab-case names, 4-space indentation
##
for file in "${STAGED[@]}"; do
    case "$file" in
        ghost/i18n/locales/*.json) ;;
        *) continue ;;
    esac

    base="$(basename "$file")"

    if ! echo "$base" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*\.json$'; then
        hook_fail "i18n filename must be kebab-case: $file"
        status=1
    fi

    if [ -f "$file" ] && grep -qE '^(\t| {1,3})"' "$file"; then
        hook_fail "i18n file must use 4-space indentation: $file"
        status=1
    fi
done

##
## 5) TypeScript strictness  (CI runs: yarn nx run-many -t build:tsc)
##
for file in "${STAGED[@]}"; do
    case "$file" in
        tsconfig.json|*/tsconfig.json|tsconfig.*.json|*/tsconfig.*.json) ;;
        *) continue ;;
    esac

    [ -f "$file" ] || continue

    if grep -qE '"strict"[[:space:]]*:[[:space:]]*false' "$file"; then
        hook_fail "\"strict\": false in $file - strict type checking is required."
        status=1
    fi
done

if [ $status -ne 0 ]; then
    echo >&2
    hook_fail "pre-commit checks failed."
    echo -e "${hook_grey}Bypass (not recommended): SKIP_HOOKS=1 git commit${hook_no_color}" >&2
fi

exit $status
PRECOMMIT
ok "wrote $HOOKS_DIR/pre-commit"

# --------------------------------------------------------------------------
# pre-push
# --------------------------------------------------------------------------

write_file "$HOOKS_DIR/pre-push" <<'PREPUSH'
#!/usr/bin/env bash
#
# Runs the same commands CI runs, against the same diff base, so a push that
# would go red is caught locally first.
#
#   yarn nx affected -t lint      -> .github/workflows/ci.yml (Lint)
#   yarn nx run-many -t build:tsc -> .github/workflows/ci.yml (Unit tests)
#   yarn nx affected -t test:unit -> .github/workflows/ci.yml (Unit tests)
#
# Bypass with SKIP_HOOKS=1 git push  (or git push --no-verify)
# Skip only the unit tests with SKIP_UNIT_TESTS=1.
#
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname -- "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/ghost-checks.sh"

hook_should_skip && exit 0
cd "$ROOT" || exit 1

if [ ! -x node_modules/.bin/nx ]; then
    hook_warn "nx not installed - skipping pre-push checks. Run 'yarn' to enable them."
    exit 0
fi

# CI diffs against the PR base. Locally the closest equivalent is the merge
# base with the default branch; fall back to HEAD~1 on a fresh clone.
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
BASE="$(git merge-base HEAD "$DEFAULT_BRANCH" 2>/dev/null || true)"

if [ -z "$BASE" ]; then
    BASE="$(git rev-parse --quiet --verify HEAD~1 2>/dev/null || true)"
fi

if [ -z "$BASE" ]; then
    hook_warn "Could not determine a diff base - skipping pre-push checks."
    exit 0
fi

status=0

hook_step "nx affected -t lint (base: ${BASE:0:8})"
if yarn nx affected -t lint --base="$BASE"; then
    hook_pass "lint clean"
else
    hook_fail "lint failed - this will fail CI."
    status=1
fi

hook_step "nx run-many -t build:tsc"
if yarn nx run-many -t build:tsc; then
    hook_pass "type check clean"
else
    hook_fail "type check failed - this will fail CI."
    status=1
fi

if [ -n "${SKIP_UNIT_TESTS:-}" ]; then
    hook_warn "SKIP_UNIT_TESTS set - skipping unit tests."
else
    hook_step "nx affected -t test:unit (base: ${BASE:0:8})"
    if yarn nx affected -t test:unit --base="$BASE"; then
        hook_pass "unit tests passed"
    else
        hook_fail "unit tests failed - this will fail CI."
        status=1
    fi
fi

if [ $status -ne 0 ]; then
    echo >&2
    hook_fail "pre-push checks failed."
    echo -e "${hook_grey}Bypass (not recommended): SKIP_HOOKS=1 git push${hook_no_color}" >&2
fi

exit $status
PREPUSH
ok "wrote $HOOKS_DIR/pre-push"

# --------------------------------------------------------------------------
# commit-msg
# --------------------------------------------------------------------------

write_file "$HOOKS_DIR/commit-msg" <<'COMMITMSG'
#!/usr/bin/env bash
#
# Ghost commit message conventions. Everything is a warning except a malformed
# issue reference, which is cheap to get right and annoying to fix afterwards.
#
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname -- "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/ghost-checks.sh"

hook_should_skip && exit 0

COMMIT_MSG_FILE="$1"
[ -f "$COMMIT_MSG_FILE" ] || exit 0

# Ignore comment lines so git's template does not skew the checks.
commit_msg="$(grep -v '^#' "$COMMIT_MSG_FILE")"

subject="$(echo "$commit_msg" | sed -n '1p')"
second_line="$(echo "$commit_msg" | sed -n '2p')"
third_line="$(echo "$commit_msg" | sed -n '3p')"
body="$(echo "$commit_msg" | tail -n +4)"

# Merge, revert and fixup commits are generated by git; leave them alone.
case "$subject" in
    Merge*|Revert*|fixup!*|squash!*) exit 0 ;;
esac

[ -z "$(echo "$subject" | tr -d '[:space:]')" ] && exit 0

status=0

if [ ${#subject} -gt 80 ]; then
    hook_warn "Subject is ${#subject} characters (max 80)."
fi

if [ -n "$second_line" ]; then
    hook_warn "Second line should be blank."
fi

if [ -n "$third_line" ]; then
    if echo "$third_line" | grep -qE '^(refs|ref:)'; then
        hook_fail "Third line starts with 'refs'/'ref:' - use 'ref <link>', 'fixes <link>' or 'closes <link>'."
        status=1
    elif ! echo "$third_line" | grep -qE '^(ref|fixes|closes) .+'; then
        hook_warn "Third line should start with 'ref', 'fixes' or 'closes' followed by an issue link."
    fi
fi

if [ -z "$(echo "$body" | tr -d '[:space:]')" ]; then
    hook_warn "No body - explain why this change was made."
fi

if ! echo "$subject" | grep -qiE '(Fixed|Changed|Updated|Improved|Added|Removed|Reverted|Moved|Released|Bumped|Cleaned)'; then
    hook_warn "Subject should use past tense (Fixed, Added, Updated, ...)."
fi

exit $status
COMMITMSG
ok "wrote $HOOKS_DIR/commit-msg"

# --------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------

for hook in pre-commit pre-push commit-msg; do
    bash -n "$HOOKS_DIR/$hook" || fail "$HOOKS_DIR/$hook has a syntax error."
done

node --check "$LINT_STAGED_CONFIG" || fail "$LINT_STAGED_CONFIG has a syntax error."

echo
ok "Git hooks installed."
cat <<SUMMARY

  pre-commit   eslint on staged files (warnings = errors), yarn-only guard,
               i18n filename + indentation guard, tsconfig strict guard
  pre-push     nx affected -t lint, nx run-many -t build:tsc,
               nx affected -t test:unit
  commit-msg   Ghost commit message conventions

  Skip once:   SKIP_HOOKS=1 git commit
  Skip tests:  SKIP_UNIT_TESTS=1 git push

SUMMARY
