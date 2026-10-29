#!/usr/bin/env bash
#
# Install or remove the DeepSeek Harness skill copies.
#
# `install` copies a built tree (scripts/build-dsh-skills.sh --all) into the DSH
# skill root and replaces only entries this checkout owns. `remove` deletes
# those entries again. Ownership means a symlink into this checkout, or a
# directory whose SKILL.md frontmatter names the same skill — a skill you wrote
# yourself under a colliding name is always left alone.
#
# Usage: bash scripts/sync-dsh-skills.sh install <build-dir> <skills-dir>
#        bash scripts/sync-dsh-skills.sh remove <skills-dir>
# Exit codes: 0 = success, 1 = usage error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    echo "usage: $0 install <build-dir> <skills-dir>" >&2
    echo "       $0 remove <skills-dir>" >&2
    exit 1
}

# A target belongs to this checkout when it is a symlink into it, or a
# directory whose SKILL.md declares the same name.
owned() {
    target="$1"
    skill="$2"
    if [ -L "$target" ]; then
        link="$(readlink "$target")"
        case "$link" in
            "$REPO_ROOT/skills/$skill" | */dist/dsh/skills/"$skill") return 0 ;;
        esac
        return 1
    fi
    [ -f "$target/SKILL.md" ] || return 1
    declared="$(sed -n 's/^name:[[:space:]]*//p' "$target/SKILL.md" | head -n 1 | tr -d '"\r')"
    [ "$declared" = "$skill" ]
}

remove_entry() {
    if [ -L "$1" ]; then
        rm "$1"
    else
        rm -rf "$1"
    fi
}

MODE="${1:-}"
case "$MODE" in
    install)
        BUILD="${2:-}"
        SKILLS="${3:-}"
        [ -n "$BUILD" ] && [ -n "$SKILLS" ] || usage
        [ -d "$BUILD" ] || { echo "error: no built tree at $BUILD" >&2; exit 1; }
        ;;
    remove)
        SKILLS="${2:-}"
        [ -n "$SKILLS" ] || usage
        ;;
    *)
        usage
        ;;
esac

if [ "$MODE" = "remove" ] && [ ! -d "$SKILLS" ]; then
    echo "No DSH skill root at $SKILLS"
    exit 0
fi
mkdir -p "$SKILLS"

CHANGED=0
SKIPPED=0

if [ "$MODE" = "install" ]; then
    for dir in "$BUILD"/*/; do
        src="${dir%/}"
        skill="$(basename "$src")"
        target="$SKILLS/$skill"
        if [ -e "$target" ] || [ -L "$target" ]; then
            if ! owned "$target" "$skill"; then
                echo "skip $skill: $target is not managed by this checkout"
                SKIPPED=$((SKIPPED + 1))
                continue
            fi
            remove_entry "$target"
        fi
        cp -R "$src" "$target"
        CHANGED=$((CHANGED + 1))
    done
    echo "Installed $CHANGED skill(s) into $SKILLS ($SKIPPED skipped)"
else
    for dir in "$REPO_ROOT"/skills/*/; do
        skill="$(basename "${dir%/}")"
        target="$SKILLS/$skill"
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            continue
        fi
        if ! owned "$target" "$skill"; then
            echo "skip $skill: $target is not managed by this checkout"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        remove_entry "$target"
        CHANGED=$((CHANGED + 1))
    done
    echo "Removed $CHANGED skill(s) from $SKILLS ($SKIPPED skipped)"
fi
