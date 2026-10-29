#!/usr/bin/env bash
#
# Build the DeepSeek Harness skill tree.
#
# DSH's user-question tool is `ask_user_question`, not Claude Code's
# `AskUserQuestion` (which `feature-forge` even spells `AskUserQuestions`).
# Skills that name that tool are copied with the name rewritten and a note
# about DSH's schema. Without --all only those adapted skills are built, which
# is what `make dsh-link` links; --all materializes every skill for the
# self-contained copy `make dsh-install` writes.
#
# The source tree is never modified — Claude Code and Kimi Code keep reading it.
#
# Usage: bash scripts/build-dsh-skills.sh [--all] [output-dir]
# Exit codes: 0 = success, 1 = usage error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALL=0
if [ "${1:-}" = "--all" ]; then
    ALL=1
    shift
fi
OUT="${1:-$REPO_ROOT/dist/dsh/skills}"

NOTE='> DeepSeek Harness exposes this as `ask_user_question`: give each question a stable `id`, and use `multi_select` (not `multiSelect`) for multi-choice.'

rm -rf "$OUT"
mkdir -p "$OUT"

BUILT=0
ADAPTED=0
for dir in "$REPO_ROOT"/skills/*/; do
    src="${dir%/}"
    name="$(basename "$src")"

    adapt=0
    if grep -rq --include='*.md' 'AskUserQuestion' "$src"; then
        adapt=1
    fi
    if [ "$ALL" -eq 0 ] && [ "$adapt" -eq 0 ]; then
        continue
    fi

    cp -R "$src" "$OUT/$name"
    BUILT=$((BUILT + 1))

    if [ "$adapt" -eq 0 ]; then
        continue
    fi

    # Rewrite every Markdown file that names the tool, plural before singular.
    while IFS= read -r file; do
        sed -e 's/AskUserQuestions/ask_user_question/g' \
            -e 's/AskUserQuestion/ask_user_question/g' \
            "$file" > "$file.new"
        mv "$file.new" "$file"
    done < <(grep -rl --include='*.md' 'AskUserQuestion' "$OUT/$name")

    # Surface the schema difference where the skill starts, after the
    # frontmatter so a YAML comment can never capture the insert.
    awk -v note="$NOTE" '
        NR == 1 && $0 == "---" { infm = 1; print; next }
        infm && $0 == "---" { infm = 0; print; next }
        { print }
        !infm && !done && /^# / { print ""; print note; done = 1 }
    ' "$OUT/$name/SKILL.md" > "$OUT/$name/SKILL.md.new"
    mv "$OUT/$name/SKILL.md.new" "$OUT/$name/SKILL.md"

    ADAPTED=$((ADAPTED + 1))
done

echo "Built $BUILT skill(s) in $OUT ($ADAPTED adapted)"
