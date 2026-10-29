#!/usr/bin/env bash
#
# Build the adapted part of the DeepSeek Harness skill tree.
#
# DSH's user-question tool is `ask_user_question`, not Claude Code's
# `AskUserQuestion` (which `feature-forge` even spells `AskUserQuestions`).
# Only the skills that name that tool are copied here, with the name rewritten
# and a note about DSH's schema; every other skill is linked straight from
# skills/ by `make dsh-link`, so it keeps tracking the source.
#
# The source tree is never modified — Claude Code and Kimi Code keep reading it.
#
# Usage: bash scripts/build-dsh-skills.sh [output-dir]
# Exit codes: 0 = success, 1 = usage error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/dist/dsh/skills}"

NOTE='> DeepSeek Harness exposes this as `ask_user_question`: give each question a stable `id`, and use `multi_select` (not `multiSelect`) for multi-choice.'

rm -rf "$OUT"
mkdir -p "$OUT"

ADAPTED=0
for dir in "$REPO_ROOT"/skills/*/; do
    src="${dir%/}"
    name="$(basename "$src")"

    if ! grep -rq --include='*.md' 'AskUserQuestion' "$src"; then
        continue
    fi

    cp -R "$src" "$OUT/$name"

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

echo "Built $ADAPTED adapted skill(s) in $OUT"
