#!/usr/bin/env bash
#
# Test the Makefile dev-link, dev-unlink, dsh-link, dsh-unlink,
# dsh-install, dsh-remove, and validate targets. Uses temporary
# directories to simulate the plugin cache and the DSH home — never
# the real ~/.claude/plugins/ or ~/.dsh/.
#
# Usage: bash scripts/test-makefile.sh
# Exit codes: 0 = all tests pass, 1 = failure

set -euo pipefail

PASS=0
FAIL=0
CLEANUP_DIRS=()

cleanup() {
    for dir in "${CLEANUP_DIRS[@]}"; do
        rm -rf "$dir"
    done
}
trap cleanup EXIT

# Helpers
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_symlink() {
    if [ -L "$1" ]; then pass "$2"; else fail "$2 (not a symlink)"; fi
}

assert_dir() {
    if [ -d "$1" ] && [ ! -L "$1" ]; then pass "$2"; else fail "$2 (not a real directory)"; fi
}

assert_not_exists() {
    if [ ! -e "$1" ]; then pass "$2"; else fail "$2 (still exists)"; fi
}

assert_exists() {
    if [ -e "$1" ]; then pass "$2"; else fail "$2 (missing)"; fi
}

assert_exit_nonzero() {
    if [ "$1" -ne 0 ]; then pass "$2"; else fail "$2 (expected failure, got exit 0)"; fi
}

assert_exit_zero() {
    if [ "$1" -eq 0 ]; then pass "$2"; else fail "$2 (expected exit 0, got $1)"; fi
}

assert_equal() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected $2, got $1)"; fi
}

assert_contains() {
    if grep -q "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

assert_not_contains() {
    if grep -q "$2" "$1" 2>/dev/null; then fail "$3 (found '$2')"; else pass "$3"; fi
}

# Setup: create a temp directory simulating the plugin cache structure
TMPDIR=$(mktemp -d)
CLEANUP_DIRS+=("$TMPDIR")

PYTHON=$(command -v python3 || command -v python)
VERSION=$("$PYTHON" -c "import json; print(json.load(open('version.json'))['version'])")
FAKE_CACHE="$TMPDIR/fullstack-dev-skills"
CACHE_DIR="$FAKE_CACHE/$VERSION"

mkdir -p "$CACHE_DIR"
echo "placeholder" > "$CACHE_DIR/SKILL.md"

echo ""
echo "========================================"
echo "Makefile Target Tests"
echo "========================================"
echo "Temp cache: $FAKE_CACHE"
echo "Version:    $VERSION"
echo ""

# ─── Test 1: dev-link creates symlink and backup ─────────────────────
echo "--- Test 1: dev-link creates symlink and backup ---"

make dev-link CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1
EXIT=$?

assert_exit_zero $EXIT "dev-link exits 0"
assert_symlink "$CACHE_DIR" "cache dir is now a symlink"
assert_dir "$CACHE_DIR.bak" "backup directory exists"

# ─── Test 2: dev-link guard — already linked ─────────────────────────
echo "--- Test 2: dev-link guard (already symlinked) ---"

EXIT=0
make dev-link CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-link fails when already symlinked"

# ─── Test 3: dev-unlink restores backup ──────────────────────────────
echo "--- Test 3: dev-unlink restores backup ---"

EXIT=0
make dev-unlink CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dev-unlink exits 0"
assert_dir "$CACHE_DIR" "cache dir is a real directory again"
assert_not_exists "$CACHE_DIR.bak" "backup removed after restore"

# ─── Test 4: dev-unlink guard — no symlink ───────────────────────────
echo "--- Test 4: dev-unlink guard (no symlink) ---"

EXIT=0
make dev-unlink CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-unlink fails when not symlinked"

# ─── Test 5: dev-link guard — backup already exists ──────────────────
echo "--- Test 5: dev-link guard (backup already exists) ---"

mkdir -p "$CACHE_DIR.bak"

EXIT=0
make dev-link CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-link fails when backup already exists"

rmdir "$CACHE_DIR.bak"

# ─── Test 6: dev-link guard — cache dir missing ─────────────────────
echo "--- Test 6: dev-link guard (cache dir missing) ---"

mv "$CACHE_DIR" "$CACHE_DIR.tmp"

EXIT=0
make dev-link CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-link fails when cache dir missing"

mv "$CACHE_DIR.tmp" "$CACHE_DIR"

# ─── Test 7: dev-unlink guard — no backup ────────────────────────────
echo "--- Test 7: dev-unlink guard (no backup) ---"

# Create a symlink without a backup to test the guard
mv "$CACHE_DIR" "$CACHE_DIR.hold"
ln -s /nonexistent "$CACHE_DIR"

EXIT=0
make dev-unlink CACHE_BASE="$FAKE_CACHE" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-unlink fails when no backup exists"

rm "$CACHE_DIR"
mv "$CACHE_DIR.hold" "$CACHE_DIR"

# ─── Test 8: validate runs without error ─────────────────────────────
echo "--- Test 8: validate ---"

EXIT=0
make validate > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "validate exits 0"

# ─── Test 9: dsh-link links every skill ──────────────────────────────
echo "--- Test 9: dsh-link creates skill symlinks ---"

FAKE_DSH="$TMPDIR/dsh-home"
FAKE_BUILD="$TMPDIR/dsh-build"
SKILL_COUNT=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

EXIT=0
make dsh-link DSH_HOME="$FAKE_DSH" DSH_BUILD="$FAKE_BUILD" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-link exits 0"
assert_symlink "$FAKE_DSH/skills/react-expert" "skill directory is a symlink"
LINK_COUNT=$(find "$FAKE_DSH/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ')
assert_equal "$LINK_COUNT" "$SKILL_COUNT" "dsh-link links every skill ($SKILL_COUNT)"

# ─── Test 10: dsh-link adapts Claude-only tool names ─────────────────
echo "--- Test 10: adapted copies rewrite AskUserQuestion ---"

assert_contains "$FAKE_DSH/skills/feature-forge/SKILL.md" "ask_user_question" "adapted skill uses the DSH tool name"
assert_not_contains "$FAKE_DSH/skills/feature-forge/SKILL.md" "AskUserQuestion" "adapted skill drops the Claude tool name"
assert_not_contains "$FAKE_DSH/skills/the-fool/references/mode-selection-guide.md" "AskUserQuestion" "adapted reference drops the Claude tool name"
assert_contains "skills/feature-forge/SKILL.md" "AskUserQuestion" "source skill is unchanged"
ADAPTED=$(find "$FAKE_DSH/skills" -mindepth 1 -maxdepth 1 -type l -exec readlink {} \; | grep -c "^$FAKE_BUILD/" || true)
assert_equal "$ADAPTED" "2" "two skills link to adapted copies"

# ─── Test 11: dsh-link is idempotent, keeps non-symlink entries ──────
echo "--- Test 11: dsh-link idempotent, skips real directories ---"

rm "$FAKE_DSH/skills/golang-pro"
mkdir -p "$FAKE_DSH/skills/golang-pro"

EXIT=0
make dsh-link DSH_HOME="$FAKE_DSH" DSH_BUILD="$FAKE_BUILD" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-link exits 0 when a real directory exists"
assert_dir "$FAKE_DSH/skills/golang-pro" "existing real directory is preserved"
assert_symlink "$FAKE_DSH/skills/react-expert" "re-linking is idempotent"

rm -rf "$FAKE_DSH/skills/golang-pro"

# ─── Test 12: dsh-unlink removes only this checkout's links ──────────
echo "--- Test 12: dsh-unlink removes own links only ---"

ln -s /nonexistent "$FAKE_DSH/skills/custom-skill"

EXIT=0
make dsh-unlink DSH_HOME="$FAKE_DSH" DSH_BUILD="$FAKE_BUILD" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-unlink exits 0"
assert_not_exists "$FAKE_DSH/skills/react-expert" "checkout link removed"
assert_not_exists "$FAKE_DSH/skills/feature-forge" "adapted-copy link removed"
assert_symlink "$FAKE_DSH/skills/custom-skill" "unrelated symlink preserved"

# ─── Test 13: dsh-unlink guard — no skill root ───────────────────────
echo "--- Test 13: dsh-unlink guard (missing skill root) ---"

EXIT=0
make dsh-unlink DSH_HOME="$TMPDIR/absent-home" DSH_BUILD="$FAKE_BUILD" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dsh-unlink fails without a skill root"

# ─── Test 14: dsh-install copies every skill ─────────────────────────
echo "--- Test 14: dsh-install copies skills ---"

FAKE_INSTALL="$TMPDIR/install-home"
FAKE_ALL="$TMPDIR/install-build"

EXIT=0
make dsh-install DSH_HOME="$FAKE_INSTALL" DSH_BUILD="$FAKE_ALL" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-install exits 0"
assert_dir "$FAKE_INSTALL/skills/react-expert" "installed skill is a real directory"
assert_contains "$FAKE_INSTALL/skills/feature-forge/SKILL.md" "ask_user_question" "installed copy is adapted"
INSTALLED=$(find "$FAKE_INSTALL/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_equal "$INSTALLED" "$SKILL_COUNT" "dsh-install copies every skill ($SKILL_COUNT)"

# ─── Test 15: dsh-install replaces only owned entries ────────────────
echo "--- Test 15: dsh-install keeps foreign entries ---"

mkdir -p "$FAKE_INSTALL/skills/custom"
printf -- '---\nname: custom\ndescription: mine\n---\n\n# Custom\n' > "$FAKE_INSTALL/skills/custom/SKILL.md"
rm -rf "$FAKE_INSTALL/skills/golang-pro"
mkdir -p "$FAKE_INSTALL/skills/golang-pro"
printf -- '---\nname: my-go\ndescription: mine\n---\n\n# Mine\n' > "$FAKE_INSTALL/skills/golang-pro/SKILL.md"

EXIT=0
make dsh-install DSH_HOME="$FAKE_INSTALL" DSH_BUILD="$FAKE_ALL" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "re-install exits 0"
assert_contains "$FAKE_INSTALL/skills/custom/SKILL.md" "mine" "unrelated skill preserved"
assert_contains "$FAKE_INSTALL/skills/golang-pro/SKILL.md" "my-go" "colliding foreign skill preserved"
assert_contains "$FAKE_INSTALL/skills/react-expert/SKILL.md" "react-expert" "owned copy refreshed"

# ─── Test 16: dsh-link leaves installed copies alone ─────────────────
echo "--- Test 16: dsh-link does not replace copies ---"

EXIT=0
make dsh-link DSH_HOME="$FAKE_INSTALL" DSH_BUILD="$FAKE_ALL" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-link exits 0 with copies present"
assert_dir "$FAKE_INSTALL/skills/react-expert" "installed copy stays a real directory"

# ─── Test 17: dsh-remove deletes only owned entries ──────────────────
echo "--- Test 17: dsh-remove removes own copies only ---"

EXIT=0
make dsh-remove DSH_HOME="$FAKE_INSTALL" > /dev/null 2>&1 || EXIT=$?

assert_exit_zero $EXIT "dsh-remove exits 0"
assert_not_exists "$FAKE_INSTALL/skills/react-expert" "installed copy removed"
assert_exists "$FAKE_INSTALL/skills/custom/SKILL.md" "unrelated skill kept"
assert_exists "$FAKE_INSTALL/skills/golang-pro/SKILL.md" "colliding foreign skill kept"

# ─── Test 18: dsh-install needs no Python ────────────────────────────
echo "--- Test 18: dsh-install runs without Python ---"

NO_PY_HOME="$TMPDIR/no-python-home"
NO_PY_BUILD="$TMPDIR/no-python-build"
ERR=$(make dsh-install PYTHON=/nonexistent-python DSH_HOME="$NO_PY_HOME" DSH_BUILD="$NO_PY_BUILD" 2>&1 >/dev/null) || ERR="make failed: $ERR"

assert_equal "$ERR" "" "dsh-install emits no Python error"
assert_dir "$NO_PY_HOME/skills/react-expert" "dsh-install installs without Python"

# ─── Test 19: dev-link explains a missing Python ─────────────────────
echo "--- Test 19: dev-link fails cleanly without Python ---"

EXIT=0
make dev-link PYTHON=/nonexistent-python CACHE_BASE="$TMPDIR/no-python-cache" > /dev/null 2>&1 || EXIT=$?

assert_exit_nonzero $EXIT "dev-link fails when Python is unavailable"

# ─── Summary ─────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
