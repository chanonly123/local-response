#!/bin/bash

# Pull latest changes from main, rebuild, and relaunch the app.
#
# This is invoked (detached, in a new Terminal window) by the running app's
# "Update App" button. A running process can't replace its own binary, so this
# script first waits for the current instance to quit, then updates + rebuilds.
#
# Robustness:
#   - Always builds from `main`, regardless of the currently checked-out branch.
#   - Auto-stashes uncommitted changes before updating and restores them after.
#   - Restores the original branch after building, so a developer keeps their
#     working branch and changes.
#   - On any failure the Terminal window is kept open with a clear message,
#     instead of silently exiting in a detached window.
#
# Usage: ./update.sh [repo-dir]

REPO_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"

# Keep the detached Terminal window open on failure so the error is visible.
fail() {
    echo ""
    echo "=== Update failed ==="
    echo "$1"
    echo ""
    read -r -p "Press Return to close this window..." _
    exit 1
}

cd "$REPO_DIR" || fail "Could not cd to $REPO_DIR"

echo "=== Updating Local Response Mapper ==="
echo "Repo: $REPO_DIR"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    fail "$REPO_DIR is not a git repository."
fi

# Wait for the running app to quit so we can safely replace its binary.
echo "Waiting for the running app to quit..."
for _ in $(seq 1 100); do
    pgrep -f "Local Response Mapper.app" >/dev/null 2>&1 || break
    sleep 0.3
done

# Remember where we started so we can restore it afterward.
ORIGINAL_BRANCH="$(git symbolic-ref -q --short HEAD)"   # empty if detached HEAD
ORIGINAL_COMMIT="$(git rev-parse HEAD)"

# Stash uncommitted changes (tracked + untracked) so the update can proceed.
DID_STASH=false
if ! git diff --quiet || ! git diff --cached --quiet || \
   [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "Stashing local changes..."
    if git stash push --include-untracked -m "update.sh auto-stash" >/dev/null 2>&1; then
        DID_STASH=true
    else
        fail "Could not stash local changes. Commit or stash them manually, then retry."
    fi
fi

# Restore the original branch (and popped stash) on the way out.
restore_state() {
    if [ -n "$ORIGINAL_BRANCH" ]; then
        if [ "$(git symbolic-ref -q --short HEAD)" != "$ORIGINAL_BRANCH" ]; then
            echo "Returning to branch '$ORIGINAL_BRANCH'..."
            git checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1
        fi
    else
        echo "Restoring detached HEAD at $ORIGINAL_COMMIT..."
        git checkout "$ORIGINAL_COMMIT" >/dev/null 2>&1
    fi

    if [ "$DID_STASH" = true ]; then
        echo "Restoring stashed changes..."
        if ! git stash pop >/dev/null 2>&1; then
            echo "WARNING: stash pop hit a conflict. Your changes are preserved in"
            echo "         'git stash list' — resolve them manually."
        fi
    fi
}

echo "Fetching latest from origin..."
git fetch origin || fail "git fetch failed (check your network/credentials)."

# Switch to main (create a local tracking branch if it doesn't exist yet).
if git show-ref --verify --quiet refs/heads/main; then
    git checkout main >/dev/null 2>&1 || { restore_state; fail "Could not checkout main."; }
else
    git checkout -b main --track origin/main >/dev/null 2>&1 \
        || { restore_state; fail "Could not create local main tracking origin/main."; }
fi

echo "Fast-forwarding main to origin/main..."
if ! git merge --ff-only origin/main; then
    restore_state
    fail "Local main has diverged from origin/main and can't fast-forward.
Resolve it manually (e.g. 'git rebase origin/main' or 'git reset --hard origin/main')."
fi

echo "Building and relaunching..."
if ! bash ./run.sh -clean; then
    restore_state
    fail "Build failed. See the xcodebuild output above."
fi

# Built and launched from main — now put the developer back where they were.
restore_state

echo ""
echo "=== Update complete ==="
