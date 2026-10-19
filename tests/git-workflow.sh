#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-workflow-test.XXXXXX")"
REPOSITORY="$TEST_ROOT/repository"
TEST_BIN="$TEST_ROOT/bin"

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_aligned_quick_actions() {
  sed -E 's/\x1B\[[0-9;]*m//g' "$1" | awk '
  /^  • / {
    git_column = index($0, "git ")
    make_column = index($0, "make ")
    if (!seen++) { expected_git = git_column; expected_make = make_column }
    if (git_column != expected_git || make_column != expected_make) exit 1
  }
  END { if (!seen) exit 1 }' || fail "Quick Actions are not aligned: $2"
}

mkdir -p "$REPOSITORY" "$TEST_BIN"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_BIN/fzf"
chmod +x "$TEST_BIN/fzf"
cp "$ROOT_DIR/Makefile" "$REPOSITORY/Makefile"
cp -R "$ROOT_DIR/make" "$REPOSITORY/make"
git -C "$REPOSITORY" init -q
git -C "$REPOSITORY" config user.name 'Workflow Test'
git -C "$REPOSITORY" config user.email workflow@example.test
printf 'tracked\n' > "$REPOSITORY/tracked.txt"
git -C "$REPOSITORY" add tracked.txt
git -C "$REPOSITORY" commit -qm 'initial workflow fixture'
printf 'untracked\n' > "$REPOSITORY/untracked.txt"

# The current long Make target is the independent output-parity reference. The
# Quick Actions are intentionally excluded because portable commands teach all
# three workflow surfaces.
(
  cd "$REPOSITORY"
  make --no-print-directory git-status | sed -E -e 's/\x1B\[[0-9;]*m//g' -e '/✓ done/,$d' -e 's/[[:space:]]+[0-9]+ [[:alpha:]]+ ago[[:space:]]*$/  <relative-time>/' > "$TEST_ROOT/make-status"
  ./make/workflow/s | sed -E -e 's/\x1B\[[0-9;]*m//g' -e '/✓ done/,$d' -e 's/[[:space:]]+[0-9]+ [[:alpha:]]+ ago[[:space:]]*$/  <relative-time>/' > "$TEST_ROOT/direct-status"
)
cmp "$TEST_ROOT/make-status" "$TEST_ROOT/direct-status" || fail 'direct status changed the Make status body'

# shellcheck disable=SC2016 # Git must store these expansions for alias runtime.
git -C "$REPOSITORY" config alias.s "$(git config --file "$ROOT_DIR/runtime/templates/git/gitconfig_aliases" --get alias.s)"
mkdir "$REPOSITORY/nested"
(
  cd "$REPOSITORY/nested"
  PATH="$REPOSITORY/make/workflow:$PATH" git s > "$TEST_ROOT/git-status"
)
sed -E 's/\x1B\[[0-9;]*m//g' "$TEST_ROOT/git-status" > "$TEST_ROOT/git-status-plain"
grep -Fq "path:      $REPOSITORY/nested" "$TEST_ROOT/git-status-plain" || \
  fail 'git s did not preserve the subdirectory invocation context'
grep -Fq 'stage and commit:' "$TEST_ROOT/git-status" || fail 'status omitted Quick Actions'
grep -Fq 'git ac' "$TEST_ROOT/git-status" || fail 'status did not teach the Git workflow surface'
grep -Fq 'make ac' "$TEST_ROOT/git-status" || fail 'status did not teach the Make workflow surface'
require_aligned_quick_actions "$TEST_ROOT/git-status" 'git s'
(
  cd "$REPOSITORY/nested"
  PATH="$REPOSITORY/make/workflow:$PATH" s > "$TEST_ROOT/direct-nested-status"
)
sed -E 's/\x1B\[[0-9;]*m//g' "$TEST_ROOT/direct-nested-status" > "$TEST_ROOT/direct-nested-status-plain"
grep -Fq "path:      $REPOSITORY/nested" "$TEST_ROOT/direct-nested-status-plain" || \
  fail 'direct s did not preserve the subdirectory invocation context'
cmp "$TEST_ROOT/git-status-plain" "$TEST_ROOT/direct-nested-status-plain" || \
  fail 'direct s changed the git s output from the same subdirectory'
(
  cd "$REPOSITORY"
  ./make/workflow/s > "$TEST_ROOT/direct-short-status"
  make --no-print-directory s > "$TEST_ROOT/make-short-status"
)
for status_output in direct-short-status make-short-status; do
  sed -E -e 's/\x1B\[[0-9;]*m//g' -e 's/[[:space:]]+[0-9]+ [[:alpha:]]+ ago[[:space:]]*$/  <relative-time>/' \
    "$TEST_ROOT/$status_output" > "$TEST_ROOT/$status_output-plain"
done
cmp "$TEST_ROOT/direct-short-status-plain" "$TEST_ROOT/make-short-status-plain" || \
  fail 'make s changed the direct workflow output'
(
  cd "$REPOSITORY"
  make --no-print-directory git-status
) > "$TEST_ROOT/long-make-status"
require_aligned_quick_actions "$TEST_ROOT/long-make-status" 'make git-status'

# Every visible adapter is exercised at its public direct and Make seams. The
# mutating operations run in preview mode so the fixture remains reusable.
for command in a c ac p l st s d ds lg af fuck bye clean df; do
  (
    cd "$REPOSITORY"
    PATH="$TEST_BIN:$PATH" DRY_RUN=1 "./make/workflow/$command" > "$TEST_ROOT/direct-$command"
    PATH="$TEST_BIN:$PATH" DRY_RUN=1 make --no-print-directory "$command" > "$TEST_ROOT/make-$command"
  )
  [[ -s $TEST_ROOT/direct-$command ]] || fail "direct $command produced no public output"
  [[ -s $TEST_ROOT/make-$command ]] || fail "make $command produced no public output"
done
for command in cm fc fm; do
  (
    cd "$REPOSITORY"
    PATH="$TEST_BIN:$PATH" DRY_RUN=1 "./make/workflow/$command" 'workflow query' > "$TEST_ROOT/direct-$command"
    PATH="$TEST_BIN:$PATH" DRY_RUN=1 make --no-print-directory "$command" 'workflow query' > "$TEST_ROOT/make-$command"
  )
  [[ -s $TEST_ROOT/direct-$command ]] || fail "direct $command did not accept its positional argument"
  [[ -s $TEST_ROOT/make-$command ]] || fail "make $command did not accept its positional argument"
done

# Every managed adapter checks repository context before it validates inputs or
# invokes an operation. `s` and `st` remain informational reports; every other
# command fails before it can perform work or emit an argument diagnostic.
OUTSIDE_REPOSITORY="$TEST_ROOT/outside-repository"
mkdir -p "$OUTSIDE_REPOSITORY"
for command in a c cm ac p l st s d ds lg af fuck bye clean df fc fm; do
  outside_status=0
  (
    cd "$OUTSIDE_REPOSITORY"
    PATH="$TEST_BIN:$PATH" DRY_RUN=1 "$REPOSITORY/make/workflow/$command"
  ) > "$TEST_ROOT/outside-$command" 2>&1 || outside_status=$?
  grep -Fq 'not a git repository' "$TEST_ROOT/outside-$command" || \
    fail "direct $command did not explain that Git context is required"
  if [[ $command == s || $command == st ]]; then
    ((outside_status == 0)) || fail "direct $command failed while reporting a missing Git repository"
  else
    ((outside_status != 0)) || fail "direct $command succeeded outside a Git repository"
  fi
done
if grep -Fq 'please specify a commit message' "$TEST_ROOT/outside-cm"; then
  fail 'direct cm validated its message before its Git repository context'
fi
for command in fc fm; do
  if grep -Fq 'please specify a query' "$TEST_ROOT/outside-$command"; then
    fail "direct $command validated its query before its Git repository context"
  fi
done

# The generated Git shell aliases preserve output parity with their direct
# surface. The native `git clean` exception is represented by `git bye`.
for command in a c cm ac p l st s d ds lg af fuck bye df fc fm; do
  git -C "$REPOSITORY" config "alias.$command" "$(git config --file "$ROOT_DIR/runtime/templates/git/gitconfig_aliases" --get "alias.$command")"
  (
    cd "$REPOSITORY/nested"
    if [[ $command == cm || $command == fc || $command == fm || $command == fuck ]]; then
      PATH="$TEST_BIN:$REPOSITORY/make/workflow:$PATH" DRY_RUN=1 "$REPOSITORY/make/workflow/$command" 'workflow query' > "$TEST_ROOT/direct-git-$command"
      PATH="$TEST_BIN:$REPOSITORY/make/workflow:$PATH" DRY_RUN=1 git "$command" 'workflow query' > "$TEST_ROOT/git-$command"
    else
      PATH="$TEST_BIN:$REPOSITORY/make/workflow:$PATH" DRY_RUN=1 "$REPOSITORY/make/workflow/$command" > "$TEST_ROOT/direct-git-$command"
      PATH="$TEST_BIN:$REPOSITORY/make/workflow:$PATH" DRY_RUN=1 git "$command" > "$TEST_ROOT/git-$command"
    fi
  )
  sed -E \
    -e 's/\x1B\[[0-9;]*m//g' \
    -e 's/[[:space:]]+[0-9]+ [[:alpha:]]+ ago[[:space:]]*$/  <relative-time>/' \
    -e 's/config: update [0-9-]+ [0-9:]+/config: update <timestamp>/g' \
    "$TEST_ROOT/direct-git-$command" > "$TEST_ROOT/direct-git-$command-normalized"
  sed -E \
    -e 's/\x1B\[[0-9;]*m//g' \
    -e 's/[[:space:]]+[0-9]+ [[:alpha:]]+ ago[[:space:]]*$/  <relative-time>/' \
    -e 's/config: update [0-9-]+ [0-9:]+/config: update <timestamp>/g' \
    "$TEST_ROOT/git-$command" > "$TEST_ROOT/git-$command-normalized"
  cmp "$TEST_ROOT/direct-git-$command-normalized" "$TEST_ROOT/git-$command-normalized" || \
    fail "git $command changed the direct workflow output"
done

# ds shows the short status line and the diff for the same working tree.
(
  cd "$REPOSITORY"
  printf 'modified\n' > tracked.txt
  ./make/workflow/ds > "$TEST_ROOT/direct-ds-dirty"
  git checkout -q -- tracked.txt
)
sed -E 's/\x1B\[[0-9;]*m//g' "$TEST_ROOT/direct-ds-dirty" > "$TEST_ROOT/direct-ds-dirty-plain"
grep -Fq ' M tracked.txt' "$TEST_ROOT/direct-ds-dirty-plain" || fail 'ds did not print the short status line'
grep -Fq '+modified' "$TEST_ROOT/direct-ds-dirty-plain" || fail 'ds did not print the diff'

printf 'PASS: managed workflow status preserves its public surfaces\n'
