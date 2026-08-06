#!/usr/bin/env bash
#
# setup-hooks.sh — wire up Husky git hooks for the Ghost monorepo.
#
# The hooks installed here mirror the checks that gate a PR in
# .github/workflows/ci.yml, so anything that would fail CI fails locally first.
#
#   CI job "Lint"      -> yarn nx affected -t lint --base=<BASE_COMMIT>
#   CI job "Build TS"  -> yarn nx run-many -t build:tsc
#
# ghost/core's `lint` script terminates in `lint:types`
# (`eslint '**/*.ts' --cache && tsc --noEmit`), so the nx lint target already
# type-checks. pre-push therefore runs the lint target rather than build:tsc:
# ghost/core's tsconfig sets neither `noEmit` nor `outDir`, so `build:tsc`
# writes .js next to sources and would dirty the working tree on every push.
#
# Re-running this script is safe; it regenerates the managed hooks and backs up
# whatever was there before.
#
# Usage:  bash setup-hooks.sh [--dry-run]
#
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

red=$'\033[0;31m'; green=$'\033[0;32m'; yellow=$'\033[1;33m'
grey=$'\033[0;90m'; bold=$'\033[1m'; nc=$'\033[0m'

log()  { printf '%s\n' "${grey}[hooks]${nc} $*"; }
ok()   { printf '%s\n' "${green}✓${nc} $*"; }
warn() { printf '%s\n' "${yellow}!${nc} $*" >&2; }
die()  { printf '%s\n' "${red}✗ $*${nc}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || die "git is not installed."

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
    || die "Not inside a git repository. Run this from the Ghost checkout."
cd "$REPO_ROOT"

[ -f package.json ] || die "No package.json at $REPO_ROOT."

command -v node >/dev/null 2>&1 || die "node is not installed."

PKG_NAME=$(node -p "require('./package.json').name || ''" 2>/dev/null || echo '')
if [ "$PKG_NAME" != "ghost-monorepo" ]; then
    warn "Expected the 'ghost-monorepo' root package, found '${PKG_NAME:-<none>}'."
    warn "Continuing anyway — hook commands may not resolve."
fi

if command -v yarn >/dev/null 2>&1; then
    YARN_MAJOR=$(yarn -v 2>/dev/null | cut -d. -f1)
    # "Package Manager Must Be Yarn v1" — 2 violations across the sampled PRs.
    if [ "$YARN_MAJOR" != "1" ]; then
        warn "Yarn v$YARN_MAJOR detected; this repo targets Yarn v1 (yarn.lock is v1)."
    fi
else
    die "yarn is not installed. Ghost uses Yarn v1 — see README."
fi

log "Repository: ${bold}${REPO_ROOT}${nc}"

# ---------------------------------------------------------------------------
# 2. Resolve the hooks directory
#
# Ghost's root package.json already declares `"prepare": "husky install
# .github/hooks"`, so hooks live in .github/hooks rather than the husky default
# of .husky. Honour whatever `prepare` says instead of hardcoding a path.
# ---------------------------------------------------------------------------

# Prints "<dir>\t<source>" so we can report accurately even when `prepare`
# explicitly names .husky.
HOOKS_INFO=$(node -e '
const s = (require("./package.json").scripts || {}).prepare || "";
const m = s.match(/husky\s+install\s+(\S+)/);
process.stdout.write(m ? m[1] + "\tprepare" : ".husky\tdefault");
' 2>/dev/null || printf '.husky\tdefault')

HOOKS_DIR=${HOOKS_INFO%%$'\t'*}
if [ "${HOOKS_INFO##*$'\t'}" = "prepare" ]; then
    HOOKS_SOURCE="from package.json \"prepare\""
else
    HOOKS_SOURCE="husky default; no \"prepare\" script found"
fi

log "Hooks directory: ${bold}${HOOKS_DIR}${nc} (${HOOKS_SOURCE})"

if [ "$DRY_RUN" = "1" ]; then
    log "${bold}--dry-run${nc}: no files will be written."
fi

# ---------------------------------------------------------------------------
# 3. Back up anything we are about to overwrite
# ---------------------------------------------------------------------------

# Kept inside .git/ so backups are never picked up by `git status` or
# accidentally committed alongside the hooks they shadow.
GIT_DIR_PATH=$(git rev-parse --git-dir)
BACKUP_DIR="$GIT_DIR_PATH/hooks-backup/$(date +%Y%m%d-%H%M%S)"
backup_taken=0

for hook in pre-commit pre-push commit-msg; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
        if [ "$DRY_RUN" = "0" ]; then
            mkdir -p "$BACKUP_DIR"
            cp -p "$HOOKS_DIR/$hook" "$BACKUP_DIR/$hook"
        fi
        backup_taken=1
    fi
done

if [ "$backup_taken" = "1" ]; then
    if [ "$DRY_RUN" = "0" ]; then
        ok "Backed up existing hooks to ${BACKUP_DIR}"
    else
        log "Would back up existing hooks."
    fi
fi

if [ "$DRY_RUN" = "0" ]; then
    mkdir -p "$HOOKS_DIR"
fi

# write_file <path> — content on stdin. Honours --dry-run.
write_file() {
    local path="$1"
    if [ "$DRY_RUN" = "1" ]; then
        cat >/dev/null
        log "Would write $path"
    else
        cat >"$path"
        chmod +x "$path"
        ok "Wrote $path"
    fi
}

# ---------------------------------------------------------------------------
# 4. Widen the lint-staged globs
#
# The committed config is {"*.js": "eslint"}. Of the Ghost review findings
# sampled, 23 were in .tsx and 11 in .ts — none of which that glob matches, so
# the majority of violations were never linted before reaching review.
# `--max-warnings=0` matches CI, where a warning fails the lint job.
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = "0" ]; then
    node <<'NODE'
const fs = require('fs');
const path = 'package.json';
const raw = fs.readFileSync(path, 'utf8');
const pkg = JSON.parse(raw);

const desired = {
    '*.{js,jsx,mjs,cjs,ts,tsx}': 'eslint --max-warnings=0',
};

if (JSON.stringify(pkg['lint-staged']) === JSON.stringify(desired)) {
    console.log('  lint-staged config already up to date');
} else {
    pkg['lint-staged'] = desired;
    // Preserve the file's existing indentation and trailing newline.
    const indentMatch = raw.match(/\n(\s+)"/);
    const indent = indentMatch ? indentMatch[1].length : 2;
    const trailing = raw.endsWith('\n') ? '\n' : '';
    fs.writeFileSync(path, JSON.stringify(pkg, null, indent) + trailing);
    console.log('  lint-staged now covers js, jsx, mjs, cjs, ts, tsx');
}
NODE
    ok "lint-staged configured"
else
    log "Would widen lint-staged to *.{js,jsx,mjs,cjs,ts,tsx}"
fi

# ---------------------------------------------------------------------------
# 5. pre-commit
#
# Changes from the previous hook:
#   - lint-staged ran only when the branch was literally `main`, so no feature
#     branch was ever linted. The guard is gone; it now runs on every branch.
#   - adds a yarn-only guard (2 violations sampled, e.g. a boot.js comment
#     recommending `npm install`).
# The submodule strip and the activitypub version bump are carried over from
# the original hook unchanged.
# ---------------------------------------------------------------------------

write_file "$HOOKS_DIR/pre-commit" <<'PRECOMMIT'
#!/bin/bash
#
# Managed by setup-hooks.sh — re-run that script to regenerate.
#
# Mirrors the CI "Lint" job at staged-file granularity.

[ -n "$CI" ] && exit 0

green='\033[0;32m'
yellow='\033[1;33m'
red='\033[0;31m'
grey='\033[0;90m'
no_color='\033[0m'

##
## 1) Lint staged files
##
## Runs on every branch. lint-staged covers js/jsx/mjs/cjs/ts/tsx with
## --max-warnings=0, matching CI, and catches the recurring findings:
## missing semicolons, double-quoted strings, `var`, wrong indentation and
## loose equality.
##

echo -e "Linting staged files ${grey}(pre-commit hook)${no_color}"

if ! yarn lint-staged --relative; then
    echo -e "${red}❌ Linting failed${no_color}" >&2
    echo -e "${yellow}Most issues auto-fix with: yarn eslint --fix <file>${no_color}" >&2
    exit 1
fi

##
## 2) Enforce Yarn v1 as the package manager
##

STAGED=$(git diff --cached --name-only --diff-filter=ACM)

if echo "$STAGED" | grep -qE '(^|/)package-lock\.json$'; then
    echo -e "${red}❌ package-lock.json is staged — Ghost uses Yarn v1${no_color}" >&2
    echo -e "   Remove it and commit yarn.lock instead." >&2
    exit 1
fi

# Only inspect added lines, so pre-existing references don't block a commit.
NPM_HITS=""
while IFS= read -r file; do
    [ -n "$file" ] || continue
    hits=$(git diff --cached -U0 -- "$file" \
        | grep -E '^\+' \
        | grep -vE '^\+\+\+' \
        | grep -E 'npm (install|i|ci|run|add)\b' || true)
    if [ -n "$hits" ]; then
        NPM_HITS="${NPM_HITS}  ${file}
$(echo "$hits" | sed 's/^/    /')
"
    fi
done < <(git diff --cached --name-only --diff-filter=ACM -- '*.js' '*.jsx' '*.ts' '*.tsx' '*.md')

if [ -n "$NPM_HITS" ]; then
    if [ "${SKIP_YARN_CHECK:-0}" = "1" ]; then
        echo -e "${yellow}! Added lines reference npm (SKIP_YARN_CHECK=1, continuing)${no_color}" >&2
        printf '%s' "$NPM_HITS" >&2
    else
        echo -e "${red}❌ Added lines reference npm; this repo standardises on Yarn v1${no_color}" >&2
        printf '%s' "$NPM_HITS" >&2
        echo -e "${yellow}  Use the yarn equivalent, or set SKIP_YARN_CHECK=1 to bypass.${no_color}" >&2
        exit 1
    fi
fi

##
## 3) Check and remove submodules before committing
##

ROOT_DIR=$(git rev-parse --show-cdup)
SUBMODULES=$(grep path ${ROOT_DIR}.gitmodules 2>/dev/null | sed 's/^.*path = //')
MOD_SUBMODULES=""
if [ -n "$SUBMODULES" ]; then
    MOD_SUBMODULES=$(git diff --cached --name-only --ignore-submodules=none | grep -F "$SUBMODULES" || true)
fi

echo -e "Checking submodules ${grey}(pre-commit hook)${no_color} "

if [[ -n "$MOD_SUBMODULES" ]]; then
    echo -e "${grey}Removing submodules from commit...${no_color}"
    for SUB in $MOD_SUBMODULES
    do
        git reset --quiet HEAD "$SUB"
        echo -e "\t${grey}removed:\t$SUB${no_color}"
    done
    echo
    echo -e "${grey}Submodules removed from commit, continuing...${no_color}"

    # If there are no changes to commit after removing submodules, abort to avoid an empty commit
    if output=$(git status --porcelain) && [ -z "$output" ]; then
        echo -e "nothing to commit, working tree clean"
        exit 1
    fi
else
    echo "No submodules in commit, continuing..."
fi

##
## 4) Suggest shipping a new version of @tryghost/activitypub when changes are detected
##    The intent is to ship smaller changes more frequently to production
##

increment_version() {
    local package_json_path=$1
    local version_type=$2

    local current_version
    current_version=$(grep '"version":' "$package_json_path" | awk -F '"' '{print $4}')

    IFS='.' read -r major minor patch <<< "$current_version"

    case "$version_type" in
        major) ((major++)); minor=0; patch=0 ;;
        minor) ((minor++)); patch=0 ;;
        patch) ((patch++)) ;;
        *) echo "Invalid version type"; exit 1 ;;
    esac

    new_version="$major.$minor.$patch"

    # Update package.json with new version
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$new_version\"/" "$package_json_path"
    else
        # Linux and others
        sed -i -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$new_version\"/" "$package_json_path"
    fi

    echo "Updated version to $new_version in $package_json_path"
}

AP_BUMP_NEEDED=false
MODIFIED_FILES=$(git diff --cached --name-only)

for FILE in $MODIFIED_FILES; do
    if [[ "$FILE" == apps/activitypub/* ]]; then
        AP_BUMP_NEEDED=true
        break
    fi
done

# Only prompt when a terminal is attached, so scripted commits don't hang.
if [[ "$AP_BUMP_NEEDED" == true ]] && [ -t 0 ] && [ -e /dev/tty ]; then
    echo -e "\nYou have made changes to @tryghost/activitypub."
    echo -e "Would you like to ship a new version? (yes)"
    read -r new_version </dev/tty

    if [[ -z "$new_version" || "$new_version" == "yes" || "$new_version" == "y" ]]; then
        echo -e "Is that a patch, minor or major? (patch)"
        read -r version_type </dev/tty

        # Default to patch
        if [[ -z "$version_type" ]]; then
            version_type="patch"
        fi

        if [[ "$version_type" != "patch" && "$version_type" != "minor" && "$version_type" != "major" ]]; then
            echo -e "${red}Invalid input. Skipping version bump.${no_color}"
        else
            echo "Bumping version ($version_type)..."
            increment_version "apps/activitypub/package.json" "$version_type"
            git add apps/activitypub/package.json
        fi
    fi
fi

echo -e "${green}✓ pre-commit checks passed${no_color}"
exit 0
PRECOMMIT

# ---------------------------------------------------------------------------
# 6. pre-push
#
# Mirrors the CI "Lint" job. `nx affected -t lint` fans out to every affected
# workspace, and for ghost/core the lint target ends in `tsc --noEmit`, so
# strict type errors surface here too.
# ---------------------------------------------------------------------------

write_file "$HOOKS_DIR/pre-push" <<'PREPUSH'
#!/bin/bash
#
# Managed by setup-hooks.sh — re-run that script to regenerate.
#
# Mirrors CI job "Lint": yarn nx affected -t lint --base=<BASE_COMMIT>
# For ghost/core the lint target ends in `lint:types` (tsc --noEmit), so this
# also type-checks. Set SKIP_PREPUSH=1 to bypass.

[ -n "$CI" ] && exit 0

if [ "${SKIP_PREPUSH:-0}" = "1" ]; then
    echo "Skipping pre-push checks (SKIP_PREPUSH=1)"
    exit 0
fi

yellow='\033[1;33m'
red='\033[0;31m'
green='\033[0;32m'
grey='\033[0;90m'
no_color='\033[0m'

# CI diffs against the PR base. Locally, the merge-base with the default
# upstream branch is the closest equivalent.
DEFAULT_BRANCH="${GHOST_DEFAULT_BRANCH:-main}"
REMOTE="${GHOST_UPSTREAM:-origin}"

BASE=""
for ref in "$REMOTE/$DEFAULT_BRANCH" "$DEFAULT_BRANCH"; do
    if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
        BASE=$(git merge-base HEAD "$ref" 2>/dev/null) && break
    fi
done

if [ -z "$BASE" ]; then
    echo -e "${yellow}! Could not resolve a merge-base against ${REMOTE}/${DEFAULT_BRANCH}.${no_color}" >&2
    echo -e "${yellow}  Skipping affected-lint; CI will still run it.${no_color}" >&2
    exit 0
fi

if [ "$BASE" = "$(git rev-parse HEAD)" ]; then
    echo "No commits ahead of ${REMOTE}/${DEFAULT_BRANCH}, nothing to lint."
    exit 0
fi

echo -e "Linting affected projects ${grey}(pre-push hook)${no_color}"
echo -e "${grey}  base: ${BASE}${no_color}"

if ! yarn nx affected -t lint --base="$BASE"; then
    echo -e "${red}❌ Lint failed — this would fail the CI \"Lint\" job${no_color}" >&2
    echo -e "${yellow}   Re-run locally with: yarn nx affected -t lint --base=$BASE${no_color}" >&2
    echo -e "${yellow}   To push anyway: SKIP_PREPUSH=1 git push${no_color}" >&2
    exit 1
fi

echo -e "${green}✓ pre-push checks passed${no_color}"
exit 0
PREPUSH

# ---------------------------------------------------------------------------
# 7. commit-msg
#
# Carried over from the repo's existing hook. The one behavioural change: the
# original reopened $EDITOR on a bad third line, which hangs a non-interactive
# commit. It now only does that when a tty is attached.
# ---------------------------------------------------------------------------

write_file "$HOOKS_DIR/commit-msg" <<'COMMITMSG'
#!/bin/bash
#
# Managed by setup-hooks.sh — re-run that script to regenerate.

# Get the commit message file path from the first argument
commit_msg_file="$1"

# Read the commit message
commit_msg=$(cat "$commit_msg_file")

# Colors for output
red='\033[0;31m'
yellow='\033[1;33m'
no_color='\033[0m'

# Get the first line (subject)
subject=$(echo "$commit_msg" | head -n1)

# Get the second line
second_line=$(echo "$commit_msg" | sed -n '2p')

# Get the third line
third_line=$(echo "$commit_msg" | sed -n '3p')

# Get the rest of the message (body)
body=$(echo "$commit_msg" | tail -n +4)

# Check subject length (max 80 characters)
if [ ${#subject} -gt 80 ]; then
    echo -e "${yellow}Warning: Commit message subject is too long (max 80 characters)${no_color}"
    echo -e "Current length: ${#subject} characters"
fi

# Check if second line is blank
if [ ! -z "$second_line" ]; then
    echo -e "${yellow}Warning: Second line should be blank${no_color}"
fi

# Check third line format
if [ ! -z "$third_line" ]; then
    if [[ "$third_line" =~ ^(refs|ref:) ]]; then
        echo -e "${red}Error: Third line should not start with 'refs' or 'ref:'${no_color}" >&2
        echo -e "Use 'ref <issue link>', 'fixes <issue link>', or 'closes <issue link>' instead" >&2

        if [ -e /dev/tty ]; then
            echo -e "${yellow}Press Enter to edit the message...${no_color}" >&2
            read < /dev/tty # Wait for Enter key press from the terminal

            # Get the configured Git editor
            editor=$(git var GIT_EDITOR)
            if [ -z "$editor" ]; then
                editor=${VISUAL:-${EDITOR:-vi}} # Fallback logic similar to Git
            fi

            # Re-open the editor on the commit message file, connected to the terminal
            $editor "$commit_msg_file" < /dev/tty

            # Re-read the potentially modified commit message after editing
            commit_msg=$(cat "$commit_msg_file")
            # Need to update related variables as well
            subject=$(echo "$commit_msg" | head -n1)
            second_line=$(echo "$commit_msg" | sed -n '2p')
            third_line=$(echo "$commit_msg" | sed -n '3p')
            body=$(echo "$commit_msg" | tail -n +4)
        fi

        # Re-check the third line *again* after editing
        if [[ "$third_line" =~ ^(refs|ref:) ]]; then
             echo -e "${red}Error: Third line still starts with 'refs' or 'ref:'. Commit aborted.${no_color}" >&2
             exit 1 # Abort commit if still invalid
        fi
        # If fixed, the script will continue to the next checks
    fi

    if ! [[ "$third_line" =~ ^(ref|fixes|closes)\ .*$ ]]; then
        echo -e "${yellow}Warning: Third line should start with 'ref', 'fixes', or 'closes' followed by an issue link${no_color}" >&2
    fi
fi

# Check for body content (why explanation)
if [ -z "$body" ]; then
    echo -e "${yellow}Warning: Missing explanation of why this change was made${no_color}"
    echo -e "The body should explain: why this, why now, why not something else?"
fi

# Check for emoji in user-facing changes
if [[ "$subject" =~ ^[^[:space:]]*[[:space:]] ]]; then
    first_word="${subject%% *}"
    if [[ ! "$first_word" =~ ^[[:punct:]] ]]; then
        echo -e "${yellow}Warning: User-facing changes should start with an emoji${no_color}"
        echo -e "Common emojis: ✨ (Feature), 🎨 (Improvement), 🐛 (Bug Fix), 🌐 (i18n), 💡 (User-facing)"
    fi
fi

# Check for past tense verbs in subject
past_tense_words="Fixed|Changed|Updated|Improved|Added|Removed|Reverted|Moved|Released|Bumped|Cleaned"
if ! echo "$subject" | grep -iE "$past_tense_words" > /dev/null; then
    echo -e "${yellow}Warning: Subject line should use past tense${no_color}"
    echo -e "Use one of: Fixed, Changed, Updated, Improved, Added, Removed, Reverted, Moved, Released, Bumped, Cleaned"
fi

exit 0
COMMITMSG

# ---------------------------------------------------------------------------
# 8. Register the hooks with git via husky
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = "1" ]; then
    log "Would run: yarn husky install $HOOKS_DIR"
    printf '\n%s\n' "${bold}Dry run complete — nothing changed.${nc}"
    exit 0
fi

# `husky install <dir>` only sets core.hooksPath, so when husky isn't on disk
# yet we can set it ourselves rather than blocking on a full dependency install.
if [ -d node_modules/husky ] && yarn husky install "$HOOKS_DIR" >/dev/null 2>&1; then
    ok "husky installed"
else
    git config core.hooksPath "$HOOKS_DIR"
    ok "core.hooksPath set directly"
    if [ ! -d node_modules/husky ]; then
        warn "husky is not in node_modules — run 'yarn install' before committing,"
        warn "otherwise the hooks will fail when they invoke lint-staged / nx."
    fi
fi

CONFIGURED=$(git config --get core.hooksPath || echo '')
if [ "$CONFIGURED" = "$HOOKS_DIR" ]; then
    ok "git core.hooksPath -> ${bold}${CONFIGURED}${nc}"
else
    die "core.hooksPath is '${CONFIGURED:-<unset>}', expected '$HOOKS_DIR'."
fi

# ---------------------------------------------------------------------------
# 9. Summary
# ---------------------------------------------------------------------------

cat <<SUMMARY

${bold}Hooks installed${nc}

  ${bold}pre-commit${nc}  lint-staged over js/jsx/mjs/cjs/ts/tsx (--max-warnings=0)
              yarn-only guard, submodule strip, activitypub version bump
  ${bold}pre-push${nc}    yarn nx affected -t lint  (includes tsc --noEmit via
              ghost/core's lint:types) — mirrors the CI "Lint" job
  ${bold}commit-msg${nc}  Ghost commit conventions

${bold}Bypasses${nc} (use sparingly — CI still enforces all of this)

  SKIP_YARN_CHECK=1 git commit ...
  SKIP_PREPUSH=1 git push
  git commit --no-verify

SUMMARY

ok "Done."
