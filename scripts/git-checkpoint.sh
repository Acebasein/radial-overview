#!/usr/bin/env bash

set -euo pipefail

# ------------------------------------------------------------
# Radial Overview - Git Checkpoint Helper
#
# Workflow:
#   1. Verify Git repository
#   2. Show branch and working-tree status
#   3. Show changed/untracked files
#   4. Show diff summary
#   5. Optional full diff review
#   6. Ask for commit message
#   7. Confirm
#   8. Stage all changes
#   9. Show staged state
#  10. Commit
#  11. Verify final repository state
#
# This script NEVER pushes automatically.
# ------------------------------------------------------------

bold() {
    printf '\033[1m%s\033[0m\n' "$1"
}

green() {
    printf '\033[32m%s\033[0m\n' "$1"
}

yellow() {
    printf '\033[33m%s\033[0m\n' "$1"
}

red() {
    printf '\033[31m%s\033[0m\n' "$1"
}

divider() {
    printf '\n%s\n' "------------------------------------------------------------"
}

# ------------------------------------------------------------
# 1. Verify repository
# ------------------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "Error: This directory is not inside a Git repository."
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

branch="$(git branch --show-current)"

divider
bold "Git Checkpoint"
printf "Repository : %s\n" "$repo_root"
printf "Branch     : %s\n" "$branch"

# ------------------------------------------------------------
# 2. Check whether anything changed
# ------------------------------------------------------------

if [[ -z "$(git status --porcelain)" ]]; then
    divider
    green "Working tree is clean. Nothing to commit."
    exit 0
fi

# ------------------------------------------------------------
# 3. Show changed files
# ------------------------------------------------------------

divider
bold "Changed files"

git status --short

# ------------------------------------------------------------
# 4. Show summary
# ------------------------------------------------------------

divider
bold "Tracked-file diff summary"

if git diff --quiet; then
    printf "No unstaged tracked-file changes.\n"
else
    git diff --stat
fi

if ! git diff --cached --quiet; then
    divider
    bold "Already staged changes"
    git diff --cached --stat
fi

untracked="$(git ls-files --others --exclude-standard)"

if [[ -n "$untracked" ]]; then
    divider
    bold "Untracked files"
    printf '%s\n' "$untracked"
fi

# ------------------------------------------------------------
# 5. Optional detailed review
# ------------------------------------------------------------

divider
read -r -p "Review the full tracked-file diff? [y/N] " review_diff

if [[ "$review_diff" =~ ^[Yy]$ ]]; then
    if command -v less >/dev/null 2>&1; then
        git diff --color=always | less -R
    else
        git diff
    fi
fi

# ------------------------------------------------------------
# 6. Ask for commit message
# ------------------------------------------------------------

divider
bold "Commit message"

commit_message=""

while [[ -z "$commit_message" ]]; do
    read -r -p "Enter commit message: " commit_message

    # Remove leading/trailing whitespace.
    commit_message="$(
        printf '%s' "$commit_message" \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    if [[ -z "$commit_message" ]]; then
        yellow "Commit message cannot be empty."
    fi
done

# ------------------------------------------------------------
# 7. Final confirmation before staging
# ------------------------------------------------------------

divider
printf "Branch  : %s\n" "$branch"
printf "Commit  : %s\n" "$commit_message"

printf '\nFiles that will be staged:\n'
git status --short

printf '\n'

read -r -p "Stage ALL listed changes and commit? [y/N] " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    yellow "Checkpoint cancelled. No files were staged or committed."
    exit 0
fi

# ------------------------------------------------------------
# 8. Stage everything
# ------------------------------------------------------------

git add -A

# ------------------------------------------------------------
# 9. Verify staged state
# ------------------------------------------------------------

divider
bold "Staged changes"

git status --short

divider
bold "Staged diff summary"

git diff --cached --stat

if git diff --cached --quiet; then
    red "Nothing is staged. Commit aborted."
    exit 1
fi

# ------------------------------------------------------------
# 10. Commit
# ------------------------------------------------------------

divider
bold "Creating commit..."

git commit -m "$commit_message"

# ------------------------------------------------------------
# 11. Final verification
# ------------------------------------------------------------

divider
bold "Verification"

git status

divider
bold "Latest commit"

git log --oneline --decorate -1

divider

if [[ -z "$(git status --porcelain)" ]]; then
    green "Checkpoint complete. Working tree is clean."
else
    yellow "Commit succeeded, but the working tree still contains changes."
    git status --short
fi

printf '\n'
yellow "Nothing was pushed. Push explicitly when you are ready."
