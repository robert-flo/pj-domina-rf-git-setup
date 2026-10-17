#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The supported development entry point is the root dispatcher, not an
# implementation file under bin/.
GIT_SETUP="$ROOT_DIR/git-setup"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/git-setup-test.XXXXXX")"
TEST_BIN="$TEST_ROOT/bin"
DEFAULT_HOME="$TEST_ROOT/default-home"
CUSTOM_HOME="$TEST_ROOT/custom-home"

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f $1 ]] || fail "missing file: $1"
}

require_output() {
  grep -Fq "$2" "$1" || fail "missing output: $2"
}

run_setup() {
  local home="$1"
  shift

  (
    cd "$TEST_ROOT"
    HOME="$home" XDG_CONFIG_HOME="$home/.config" TERM=dumb PATH="$TEST_BIN:$PATH" "$GIT_SETUP" "$@"
  )
}

mkdir -p "$TEST_BIN" "$DEFAULT_HOME" "$CUSTOM_HOME"

# Keep tests offline and prevent access to the developer's GitHub, SSH, or GPG
# sessions. The commands are present so `verify` exercises its complete flow.
for command in gh ssh ssh-add pgrep delta gpgconf; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TEST_BIN/$command"
  chmod +x "$TEST_BIN/$command"
done

# shellcheck disable=SC2016 # The stub must receive a literal parameter expansion.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  --list-secret-keys) exit 0 ;;' \
  '  --clearsign) cat; exit 0 ;;' \
  'esac' \
  'exit 0' > "$TEST_BIN/gpg"
chmod +x "$TEST_BIN/gpg"

# Missing dependencies stop the public command before it does any work. The
# detected package manager is guidance only: neither it nor sudo may run.
MISSING_DEPENDENCY_BIN="$TEST_ROOT/missing-dependency-bin"
DEPENDENCY_EXECUTION_MARKER="$TEST_ROOT/dependency-command-executed"
MISSING_DEPENDENCY_HOME="$TEST_ROOT/missing-dependency-home"
mkdir -p "$MISSING_DEPENDENCY_BIN" "$MISSING_DEPENDENCY_HOME"

for command in bash chmod cp dirname git mkdir realpath gpg ssh-keygen; do
  ln -s "$(command -v "$command")" "$MISSING_DEPENDENCY_BIN/$command"
done

printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$MISSING_DEPENDENCY_BIN/delta"
# shellcheck disable=SC2016 # The generated stubs expand these values when run.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "executed: %s\n" "${0##*/}" >> "$DEPENDENCY_EXECUTION_MARKER"' \
  'exit 99' > "$MISSING_DEPENDENCY_BIN/apt"
cp "$MISSING_DEPENDENCY_BIN/apt" "$MISSING_DEPENDENCY_BIN/sudo"
chmod +x "$MISSING_DEPENDENCY_BIN/delta" "$MISSING_DEPENDENCY_BIN/apt" "$MISSING_DEPENDENCY_BIN/sudo"

missing_dependency_status=0
PATH="$MISSING_DEPENDENCY_BIN" \
  HOME="$MISSING_DEPENDENCY_HOME" \
  XDG_CONFIG_HOME="$MISSING_DEPENDENCY_HOME/.config" \
  TERM=dumb \
  DEPENDENCY_EXECUTION_MARKER="$DEPENDENCY_EXECUTION_MARKER" \
  "$GIT_SETUP" config > "$TEST_ROOT/missing-dependency-output" 2>&1 || missing_dependency_status=$?

((missing_dependency_status != 0)) || fail 'missing dependency did not stop git-setup'
require_output "$TEST_ROOT/missing-dependency-output" 'gh not found'
require_output "$TEST_ROOT/missing-dependency-output" 'Ubuntu/Debian (detected):'
require_output "$TEST_ROOT/missing-dependency-output" 'sudo apt install git gh gnupg openssh-client git-delta'
require_output "$TEST_ROOT/missing-dependency-output" 'Arch Linux:'
require_output "$TEST_ROOT/missing-dependency-output" 'sudo pacman -S --needed git github-cli gnupg openssh git-delta'
require_output "$TEST_ROOT/missing-dependency-output" 'Fedora:'
require_output "$TEST_ROOT/missing-dependency-output" 'sudo dnf install git gh gnupg2 openssh-clients git-delta'
require_output "$TEST_ROOT/missing-dependency-output" 'After installing the missing packages, run git-setup again.'
[[ ! -e $DEPENDENCY_EXECUTION_MARKER ]] || fail 'dependency guidance executed a privileged package command'
[[ ! -e $MISSING_DEPENDENCY_HOME/.config/git/config ]] || fail 'missing dependency allowed configuration changes'

# Each other supported manager is also selected when it is the available one.
for package_manager in pacman dnf; do
  manager_bin="$TEST_ROOT/$package_manager-bin"
  mkdir -p "$manager_bin"
  for command in bash dirname realpath git gpg ssh-keygen; do
    ln -s "$(command -v "$command")" "$manager_bin/$command"
  done
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$manager_bin/delta"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 99' > "$manager_bin/$package_manager"
  chmod +x "$manager_bin/delta" "$manager_bin/$package_manager"

  manager_status=0
  PATH="$manager_bin" TERM=dumb \
    "$GIT_SETUP" config > "$TEST_ROOT/$package_manager-output" 2>&1 || manager_status=$?
  ((manager_status != 0)) || fail "$package_manager guidance did not stop git-setup"

  case $package_manager in
    pacman) require_output "$TEST_ROOT/$package_manager-output" 'Arch Linux (detected):' ;;
    dnf) require_output "$TEST_ROOT/$package_manager-output" 'Fedora (detected):' ;;
  esac
done

# Without a supported package manager, the failure names every required
# command and still gives the user all three supported installation paths.
NO_PACKAGE_MANAGER_BIN="$TEST_ROOT/no-package-manager-bin"
mkdir -p "$NO_PACKAGE_MANAGER_BIN"
for command in bash cat dirname realpath; do
  ln -s "$(command -v "$command")" "$NO_PACKAGE_MANAGER_BIN/$command"
done

no_package_manager_status=0
PATH="$NO_PACKAGE_MANAGER_BIN" TERM=dumb \
  "$GIT_SETUP" config > "$TEST_ROOT/no-package-manager-output" 2>&1 || no_package_manager_status=$?

((no_package_manager_status != 0)) || fail 'missing dependencies without a package manager did not stop git-setup'
require_output "$TEST_ROOT/no-package-manager-output" 'Missing commands: git gh gpg ssh-keygen delta'
require_output "$TEST_ROOT/no-package-manager-output" 'No supported package manager detected (pacman, apt, or dnf).'
require_output "$TEST_ROOT/no-package-manager-output" 'Install packages that provide: git gh gpg ssh-keygen delta.'
require_output "$TEST_ROOT/no-package-manager-output" 'sudo pacman -S --needed git github-cli gnupg openssh git-delta'
require_output "$TEST_ROOT/no-package-manager-output" 'sudo apt install git gh gnupg openssh-client git-delta'
require_output "$TEST_ROOT/no-package-manager-output" 'sudo dnf install git gh gnupg2 openssh-clients git-delta'

# Global help is intentionally available before operational dependency checks.
global_help_status=0
PATH="$NO_PACKAGE_MANAGER_BIN" TERM=dumb \
  "$GIT_SETUP" --help > "$TEST_ROOT/global-help-output" 2>&1 || global_help_status=$?
((global_help_status == 0)) || fail 'global help required operational dependencies'
require_output "$TEST_ROOT/global-help-output" 'GITHUB TOKEN'
if grep -Fq 'Missing commands:' "$TEST_ROOT/global-help-output"; then
  fail 'global help ran dependency validation'
fi

# Every autonomous command exposes help without performing its operation.
for command in config verify setup test clean; do
  command_help_status=0
  PATH="$NO_PACKAGE_MANAGER_BIN" \
    HOME="$TEST_ROOT/help-home" XDG_CONFIG_HOME="$TEST_ROOT/help-home/.config" \
    TERM=dumb "$ROOT_DIR/runtime/scripts/$command" --help > "$TEST_ROOT/$command-help-output" 2>&1 || command_help_status=$?
  ((command_help_status == 0)) || fail "$command --help failed without dependencies"
  require_output "$TEST_ROOT/$command-help-output" "Usage: git-setup $command [-h|--help]"

  command_help_status=0
  PATH="$NO_PACKAGE_MANAGER_BIN" \
    HOME="$TEST_ROOT/help-home" XDG_CONFIG_HOME="$TEST_ROOT/help-home/.config" \
    TERM=dumb "$ROOT_DIR/runtime/scripts/$command" -h > "$TEST_ROOT/$command-short-help-output" 2>&1 || command_help_status=$?
  ((command_help_status == 0)) || fail "$command -h failed without dependencies"
  require_output "$TEST_ROOT/$command-short-help-output" "Usage: git-setup $command [-h|--help]"
done
PATH="$NO_PACKAGE_MANAGER_BIN" HOME="$TEST_ROOT/help-home" TERM=dumb \
  "$ROOT_DIR/runtime/scripts/help" --help > "$TEST_ROOT/help-module-output"
require_output "$TEST_ROOT/help-module-output" 'GITHUB TOKEN'

# Arguments after a command reach that module and invalid options fail before
# any command-specific operation mutates the user's configuration.
INVALID_OPTION_HOME="$TEST_ROOT/invalid-option-home"
mkdir -p "$INVALID_OPTION_HOME"
invalid_option_status=0
run_setup "$INVALID_OPTION_HOME" config --invalid > "$TEST_ROOT/invalid-option-output" 2>&1 || invalid_option_status=$?
((invalid_option_status != 0)) || fail 'invalid command option unexpectedly succeeded'
require_output "$TEST_ROOT/invalid-option-output" 'Unknown option for config: --invalid'
require_output "$TEST_ROOT/invalid-option-output" 'Usage: git-setup config [-h|--help]'
[[ ! -e $INVALID_OPTION_HOME/.config/git/config ]] || fail 'invalid command option changed configuration'

generated_files=(
  config
  delta.gitconfig
  gitattributes.global
  gitconfig_aliases
  gitignore.global
  shell_aliases
)
workflow_commands=(
  .git-workflow
  a c cm ac p l st s d lg af fuck bye clean df fc fm
)

# Default generation copies each managed template and writes the Git identity.
run_setup "$DEFAULT_HOME" config > "$TEST_ROOT/default-config-output"
for file in "${generated_files[@]}"; do
  require_file "$DEFAULT_HOME/.config/git/$file"
done
for command in "${workflow_commands[@]}"; do
  [[ -x $DEFAULT_HOME/bin/$command ]] || fail "managed workflow command is not executable: $command"
done

default_config="$DEFAULT_HOME/.config/git/config"
[[ $(git config --file "$default_config" --get user.name) == 'Roberto Flores' ]] || fail 'default name was not generated'
[[ $(git config --file "$default_config" --get user.email) == '25asab015@ujmd.edu.sv' ]] || fail 'default email was not generated'
# shellcheck disable=SC2088 # The configured value intentionally contains a literal tilde.
[[ $(git config --file "$default_config" --get user.signingkey) == '~/.ssh/id_ed25519.pub' ]] || fail 'SSH signing key was not generated'
[[ $(git config --file "$default_config" --get gpg.format) == 'ssh' ]] || fail 'SSH signing format was not generated'
[[ $(git config --file "$default_config" --get core.pager) == 'delta' ]] || fail 'Delta pager was not generated'
require_output "$TEST_ROOT/default-config-output" 'Git Configuration Files'
require_output "$TEST_ROOT/default-config-output" 'Git + GitHub + GPG Configuration for Arch Linux'
require_output "$TEST_ROOT/default-config-output" 'Created:'
require_output "$TEST_ROOT/default-config-output" 'Persistent Git customization:'

# A generated Git alias resolves the installed managed command and preserves
# the subdirectory that initiated the command.
WORKFLOW_REPOSITORY="$TEST_ROOT/workflow-repository"
mkdir -p "$WORKFLOW_REPOSITORY/nested"
git -C "$WORKFLOW_REPOSITORY" init -q
git -C "$WORKFLOW_REPOSITORY" config user.name 'Workflow Test'
git -C "$WORKFLOW_REPOSITORY" config user.email workflow@example.test
printf 'fixture\n' > "$WORKFLOW_REPOSITORY/fixture.txt"
git -C "$WORKFLOW_REPOSITORY" add fixture.txt
git -C "$WORKFLOW_REPOSITORY" commit -qm 'workflow fixture'
(
  cd "$WORKFLOW_REPOSITORY/nested"
  HOME="$DEFAULT_HOME" XDG_CONFIG_HOME="$DEFAULT_HOME/.config" \
    PATH="$DEFAULT_HOME/bin:$TEST_BIN:$PATH" git s
) > "$TEST_ROOT/installed-git-s-output"
sed -E 's/\x1B\[[0-9;]*m//g' "$TEST_ROOT/installed-git-s-output" > "$TEST_ROOT/installed-git-s-plain-output"
require_output "$TEST_ROOT/installed-git-s-plain-output" "path:      $WORKFLOW_REPOSITORY/nested"
require_output "$TEST_ROOT/installed-git-s-output" 'git ac'
require_output "$TEST_ROOT/installed-git-s-output" 'make ac'

# Installed workflow commands reject an invocation outside a repository before
# validating their operation-specific arguments.  This keeps `cm` consistent
# with the repository-context diagnostic already shown by `s`.
outside_cm_status=0
(
  cd "$TEST_ROOT"
  HOME="$DEFAULT_HOME" XDG_CONFIG_HOME="$DEFAULT_HOME/.config" \
    PATH="$DEFAULT_HOME/bin:$TEST_BIN:$PATH" cm
) > "$TEST_ROOT/installed-cm-outside-output" 2>&1 || outside_cm_status=$?
((outside_cm_status != 0)) || fail 'installed cm succeeded outside a Git repository'
require_output "$TEST_ROOT/installed-cm-outside-output" 'not a git repository'
if grep -Fq 'please specify a commit message' "$TEST_ROOT/installed-cm-outside-output"; then
  fail 'installed cm validated its message before its Git repository context'
fi

# A subsequent run refreshes managed files, preserves the local override, and
# removes legacy managed leftovers from ~/.local/bin while preserving unrelated
# ~/.local/bin user tools (even with colliding names like `s`) and symlinks.
printf '[user]\n\tname = Local Override\n' > "$DEFAULT_HOME/.config/git/gitconfig.local"
mkdir -p "$DEFAULT_HOME/.local/bin"
cp "$ROOT_DIR/make/workflow/s" "$DEFAULT_HOME/.local/bin/s"
cp "$ROOT_DIR/make/workflow/.git-workflow" "$DEFAULT_HOME/.local/bin/.git-workflow"
ln -s "$DEFAULT_HOME/bin/p" "$DEFAULT_HOME/.local/bin/p"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$DEFAULT_HOME/.local/bin/unrelated-tool"
chmod +x "$DEFAULT_HOME/.local/bin/s" "$DEFAULT_HOME/.local/bin/.git-workflow" "$DEFAULT_HOME/.local/bin/unrelated-tool"
run_setup "$DEFAULT_HOME" config > "$TEST_ROOT/updated-config-output"
require_output "$TEST_ROOT/updated-config-output" 'Updated:'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/updated-config-output" 'Removed legacy: ~/.local/bin/s'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/updated-config-output" 'Removed legacy: ~/.local/bin/.git-workflow'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/updated-config-output" 'kept unrelated ~/.local/bin/p'
require_file "$DEFAULT_HOME/.config/git/gitconfig.local"
grep -Fq 'Local Override' "$DEFAULT_HOME/.config/git/gitconfig.local" || fail 'gitconfig.local was overwritten'
[[ ! -e $DEFAULT_HOME/.local/bin/s ]] || fail 'config did not remove legacy ~/.local/bin/s leftover'
[[ ! -e $DEFAULT_HOME/.local/bin/.git-workflow ]] || fail 'config did not remove legacy ~/.local/bin/.git-workflow leftover'
[[ -L $DEFAULT_HOME/.local/bin/p ]] || fail 'config removed a symlink in ~/.local/bin'
[[ -x $DEFAULT_HOME/bin/p ]] || fail 'config followed and removed a symlink target in ~/bin'
[[ -x $DEFAULT_HOME/.local/bin/unrelated-tool ]] || fail 'config removed an unrelated ~/.local/bin tool'

printf '#!/bin/sh\necho mine\n' > "$DEFAULT_HOME/.local/bin/s"
chmod +x "$DEFAULT_HOME/.local/bin/s"
run_setup "$DEFAULT_HOME" config > "$TEST_ROOT/unrelated-s-config-output"
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/unrelated-s-config-output" 'kept unrelated ~/.local/bin/s'
[[ -x $DEFAULT_HOME/.local/bin/s ]] || fail 'config removed an unrelated ~/.local/bin/s user tool'
grep -Fq 'echo mine' "$DEFAULT_HOME/.local/bin/s" || fail 'config modified an unrelated ~/.local/bin/s user tool'

# GIT_SETUP_BIN_DIR overrides the workflow command install directory, normalizes
# trailing slashes, and takes precedence over WORKFLOW_COMMAND_DIR; meanwhile
# WORKFLOW_COMMAND_DIR still works as a backward-compatible alias when set alone.
OVERRIDE_HOME="$TEST_ROOT/override-home"
mkdir -p "$OVERRIDE_HOME"
GIT_SETUP_BIN_DIR="$OVERRIDE_HOME/custom-bin///" \
  WORKFLOW_COMMAND_DIR="$OVERRIDE_HOME/ignored-bin" \
  run_setup "$OVERRIDE_HOME" config > "$TEST_ROOT/override-config-output"
for command in "${workflow_commands[@]}"; do
  [[ -x $OVERRIDE_HOME/custom-bin/$command ]] || fail "GIT_SETUP_BIN_DIR did not install $command"
done
[[ ! -d $OVERRIDE_HOME/ignored-bin ]] || fail 'WORKFLOW_COMMAND_DIR overrode GIT_SETUP_BIN_DIR'
require_output "$TEST_ROOT/override-config-output" "Created: $OVERRIDE_HOME/custom-bin/s"

ALIAS_DIR_HOME="$TEST_ROOT/alias-dir-home"
mkdir -p "$ALIAS_DIR_HOME"
WORKFLOW_COMMAND_DIR="$ALIAS_DIR_HOME/compat-bin/" \
  run_setup "$ALIAS_DIR_HOME" config > "$TEST_ROOT/compat-config-output"
[[ -x $ALIAS_DIR_HOME/compat-bin/s ]] || fail 'WORKFLOW_COMMAND_DIR compatibility alias did not install s'
require_output "$TEST_ROOT/compat-config-output" "Created: $ALIAS_DIR_HOME/compat-bin/s"

# NAME and EMAIL provide a non-interactive identity for automation.
NAME='Ada Lovelace' EMAIL='ada@example.com' run_setup "$CUSTOM_HOME" config > "$TEST_ROOT/custom-config-output"
custom_config="$CUSTOM_HOME/.config/git/config"
[[ $(git config --file "$custom_config" --get user.name) == 'Ada Lovelace' ]] || fail 'NAME was not generated'
[[ $(git config --file "$custom_config" --get user.email) == 'ada@example.com' ]] || fail 'EMAIL was not generated'

# Verification reports its own section for all generated files without relying
# on the workstation's credentials or keyring, and hints when ~/bin is missing
# from PATH or ordered after ~/.local/bin.
run_setup "$CUSTOM_HOME" verify > "$TEST_ROOT/verify-output" || true
require_output "$TEST_ROOT/verify-output" 'Git + GitHub + GPG Configuration for Arch Linux'
require_output "$TEST_ROOT/verify-output" 'Generated Git Configuration Files'
for file in "${generated_files[@]}"; do
  require_output "$TEST_ROOT/verify-output" "Found: ~/.config/git/$file"
done
for command in "${workflow_commands[@]}"; do
  require_output "$TEST_ROOT/verify-output" "Found: ~/bin/$command"
done
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/verify-output" '~/bin is not in PATH'
require_output "$TEST_ROOT/verify-output" 'Hint:'
for command in a c cm ac p l st s d lg af fuck bye df fc fm; do
  require_output "$TEST_ROOT/verify-output" "Alias: git $command"
done

(
  cd "$TEST_ROOT"
  HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_HOME/.config" TERM=dumb \
    PATH="$CUSTOM_HOME/.local/bin:$CUSTOM_HOME/bin:$TEST_BIN:$PATH" "$GIT_SETUP" verify
) > "$TEST_ROOT/verify-path-order-output" 2>&1 || true
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/verify-path-order-output" '~/bin is after ~/.local/bin in PATH'
require_output "$TEST_ROOT/verify-path-order-output" 'Hint:'

(
  cd "$TEST_ROOT"
  HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_HOME/.config" TERM=dumb \
    PATH="$CUSTOM_HOME/bin:$CUSTOM_HOME/.local/bin:$TEST_BIN:$PATH" "$GIT_SETUP" verify
) > "$TEST_ROOT/verify-path-ok-output" 2>&1 || true
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/verify-path-ok-output" 'PATH includes ~/bin'

# An alias defined by the repository must still be reported as an override of
# the globally managed workflow alias.
ALIAS_OVERRIDE_REPOSITORY="$TEST_ROOT/alias-override-repository"
mkdir -p "$ALIAS_OVERRIDE_REPOSITORY"
git -C "$ALIAS_OVERRIDE_REPOSITORY" init -q
git -C "$ALIAS_OVERRIDE_REPOSITORY" config alias.a status
(
  cd "$ALIAS_OVERRIDE_REPOSITORY"
  HOME="$CUSTOM_HOME" XDG_CONFIG_HOME="$CUSTOM_HOME/.config" TERM=dumb \
    PATH="$TEST_BIN:$PATH" "$GIT_SETUP" verify
) > "$TEST_ROOT/alias-override-output" 2>&1 || true
require_output "$TEST_ROOT/alias-override-output" 'Alias override: git a'

# A stale SSH_AUTH_SOCK must be diagnosed as an unavailable agent socket, not
# as an agent that failed to load a valid key.
SSH_VERIFY_HOME="$TEST_ROOT/ssh-verify-home"
mkdir -p "$SSH_VERIFY_HOME/.ssh"
printf '%s\n' 'test-private-key' > "$SSH_VERIFY_HOME/.ssh/id_ed25519"
printf '%s\n' 'ssh-ed25519 AAAATEST test@example.test' > "$SSH_VERIFY_HOME/.ssh/id_ed25519.pub"
SSH_AUTH_SOCK="$TEST_ROOT/stale-agent.socket" \
  run_setup "$SSH_VERIFY_HOME" verify > "$TEST_ROOT/stale-ssh-output" || true
require_output "$TEST_ROOT/stale-ssh-output" 'SSH agent socket unavailable'
if grep -Fq 'Failed to load SSH key' "$TEST_ROOT/stale-ssh-output"; then
  fail 'stale SSH socket attempted to load the key'
fi

# Clean must disclose the managed files and remain non-destructive until 'yes'.
printf 'no\n' | run_setup "$CUSTOM_HOME" clean > "$TEST_ROOT/clean-output"
require_output "$TEST_ROOT/clean-output" 'Git Configuration:'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/clean-output" '~/.config/git/config'
require_output "$TEST_ROOT/clean-output" 'gitconfig.local will be preserved'
require_output "$TEST_ROOT/clean-output" 'Cancelled'
require_file "$CUSTOM_HOME/.config/git/config"

# Confirmed cleanup removes the owned workflow set from ~/bin and any legacy
# managed leftovers from ~/.local/bin, while never deleting ~/bin, ~/.local/bin,
# symlinks, or unrelated commands in either directory.
mkdir -p "$CUSTOM_HOME/bin" "$CUSTOM_HOME/.local/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$CUSTOM_HOME/bin/unrelated-bin-command"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$CUSTOM_HOME/.local/bin/unrelated-command"
cp "$ROOT_DIR/make/workflow/s" "$CUSTOM_HOME/.local/bin/s"
cp "$ROOT_DIR/make/workflow/clean" "$CUSTOM_HOME/.local/bin/clean"
cp "$ROOT_DIR/make/workflow/.git-workflow" "$CUSTOM_HOME/.local/bin/.git-workflow"
ln -s "$CUSTOM_HOME/bin/unrelated-bin-command" "$CUSTOM_HOME/.local/bin/p"
chmod +x \
  "$CUSTOM_HOME/bin/unrelated-bin-command" \
  "$CUSTOM_HOME/.local/bin/unrelated-command" \
  "$CUSTOM_HOME/.local/bin/s" \
  "$CUSTOM_HOME/.local/bin/clean" \
  "$CUSTOM_HOME/.local/bin/.git-workflow"
printf 'yes\n' | run_setup "$CUSTOM_HOME" clean > "$TEST_ROOT/confirmed-clean-output"
[[ ! -e $CUSTOM_HOME/bin/s ]] || fail 'clean preserved a managed workflow command in ~/bin'
[[ ! -e $CUSTOM_HOME/bin/.git-workflow ]] || fail 'clean preserved the managed workflow runtime in ~/bin'
[[ -x $CUSTOM_HOME/bin/unrelated-bin-command ]] || fail 'clean removed an unrelated ~/bin command'
[[ ! -e $CUSTOM_HOME/.local/bin/s ]] || fail 'clean preserved a legacy managed workflow command in ~/.local/bin'
[[ ! -e $CUSTOM_HOME/.local/bin/clean ]] || fail 'clean preserved a legacy managed clean command in ~/.local/bin'
[[ ! -e $CUSTOM_HOME/.local/bin/.git-workflow ]] || fail 'clean preserved the legacy managed workflow runtime in ~/.local/bin'
[[ -L $CUSTOM_HOME/.local/bin/p ]] || fail 'clean removed a symlink in ~/.local/bin'
[[ -x $CUSTOM_HOME/.local/bin/unrelated-command ]] || fail 'clean removed an unrelated ~/.local/bin command'
[[ -d $CUSTOM_HOME/.local/bin ]] || fail 'clean removed the ~/.local/bin directory'
require_output "$TEST_ROOT/confirmed-clean-output" 'Cleaning Managed Workflow Commands'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/confirmed-clean-output" 'Removed ~/bin/s'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/confirmed-clean-output" 'Removed ~/.local/bin/s'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/confirmed-clean-output" 'Removed ~/.local/bin/.git-workflow'
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/confirmed-clean-output" 'kept unrelated ~/.local/bin/p'

printf '#!/bin/sh\necho mine\n' > "$CUSTOM_HOME/.local/bin/s"
chmod +x "$CUSTOM_HOME/.local/bin/s"
printf 'yes\n' | run_setup "$CUSTOM_HOME" clean > "$TEST_ROOT/unrelated-s-clean-output"
# shellcheck disable=SC2088 # The expected user-facing path intentionally contains a literal tilde.
require_output "$TEST_ROOT/unrelated-s-clean-output" 'kept unrelated ~/.local/bin/s'
[[ -x $CUSTOM_HOME/.local/bin/s ]] || fail 'clean removed an unrelated ~/.local/bin/s user tool'
grep -Fq 'echo mine' "$CUSTOM_HOME/.local/bin/s" || fail 'clean modified an unrelated ~/.local/bin/s user tool'

# The integration test requires the identity generated by setup. Without it,
# it must not create a repository or prompt for a GitHub push.
UNCONFIGURED_HOME="$TEST_ROOT/unconfigured-home"
mkdir -p "$UNCONFIGURED_HOME"
run_setup "$UNCONFIGURED_HOME" test > "$TEST_ROOT/test-prerequisite-output" || true
require_output "$TEST_ROOT/test-prerequisite-output" 'Git identity is not configured'
require_output "$TEST_ROOT/test-prerequisite-output" 'Run option 2 (Run full setup) before the integration test'
if grep -Fq 'Push to GitHub?' "$TEST_ROOT/test-prerequisite-output"; then
  fail 'integration test offered a GitHub push without an identity'
fi

# Direct command failures must cross the public dispatcher unchanged and must
# never fall through into the interactive menu.
direct_test_status=0
run_setup "$UNCONFIGURED_HOME" test > "$TEST_ROOT/direct-test-output" 2>&1 || direct_test_status=$?
((direct_test_status != 0)) || fail 'direct test command swallowed its failure status'
if grep -Fq 'Choose an action' "$TEST_ROOT/direct-test-output"; then
  fail 'direct test command fell through into the interactive menu'
fi

# Unknown commands must fail clearly instead of silently opening the menu.
UNKNOWN_HOME="$TEST_ROOT/unknown-command-home"
mkdir -p "$UNKNOWN_HOME"
unknown_command_status=0
run_setup "$UNKNOWN_HOME" unknown > "$TEST_ROOT/unknown-command-output" 2>&1 || unknown_command_status=$?
((unknown_command_status != 0)) || fail 'unknown command unexpectedly succeeded'
require_output "$TEST_ROOT/unknown-command-output" 'Unknown command: unknown'
if grep -Fq 'Choose an action' "$TEST_ROOT/unknown-command-output"; then
  fail 'unknown command opened the interactive menu'
fi
if [[ -e "$UNKNOWN_HOME/.config/git/config" ]]; then
  fail 'unknown command mutated configuration'
fi

# Command modules remain directly executable, independent of the menu and
# root dispatcher.
DIRECT_MODULE_HOME="$TEST_ROOT/direct-module-home"
mkdir -p "$DIRECT_MODULE_HOME"
NAME='Direct Module User' EMAIL='direct-module@example.test' \
  HOME="$DIRECT_MODULE_HOME" XDG_CONFIG_HOME="$DIRECT_MODULE_HOME/.config" \
  TERM=dumb PATH="$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/config" > "$TEST_ROOT/direct-module-output"
require_file "$DIRECT_MODULE_HOME/.config/git/config"
require_output "$TEST_ROOT/direct-module-output" 'Git Configuration Files'

# Each command remains independently executable at the public runtime seam.
run_direct_verify_status=0
HOME="$DIRECT_MODULE_HOME" XDG_CONFIG_HOME="$DIRECT_MODULE_HOME/.config" \
  TERM=dumb PATH="$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/verify" > "$TEST_ROOT/direct-verify-output" 2>&1 || run_direct_verify_status=$?
((run_direct_verify_status != 0)) || fail 'direct verify unexpectedly succeeded with missing credentials'
require_output "$TEST_ROOT/direct-verify-output" 'Generated Git Configuration Files'

printf 'no\n' | HOME="$DIRECT_MODULE_HOME" XDG_CONFIG_HOME="$DIRECT_MODULE_HOME/.config" \
  TERM=dumb PATH="$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/clean" > "$TEST_ROOT/direct-clean-output"
require_output "$TEST_ROOT/direct-clean-output" 'Cancelled'

DIRECT_TEST_HOME="$TEST_ROOT/direct-test-home"
mkdir -p "$DIRECT_TEST_HOME"
direct_module_test_status=0
HOME="$DIRECT_TEST_HOME" XDG_CONFIG_HOME="$DIRECT_TEST_HOME/.config" \
  TERM=dumb PATH="$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/test" > "$TEST_ROOT/direct-module-test-output" 2>&1 || direct_module_test_status=$?
((direct_module_test_status != 0)) || fail 'direct integration test unexpectedly succeeded without identity'
require_output "$TEST_ROOT/direct-module-test-output" 'Git identity is not configured'
((direct_test_status == direct_module_test_status)) || fail 'dispatcher changed the direct test exit status'

setup_invalid_status=0
HOME="$DIRECT_TEST_HOME" XDG_CONFIG_HOME="$DIRECT_TEST_HOME/.config" \
  TERM=dumb PATH="$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/setup" --invalid > "$TEST_ROOT/direct-setup-invalid-output" 2>&1 || setup_invalid_status=$?
((setup_invalid_status != 0)) || fail 'direct setup accepted an invalid option'
require_output "$TEST_ROOT/direct-setup-invalid-output" 'Unknown option for setup: --invalid'

# A fully stubbed setup exercises the direct success seam without contacting
# GitHub or touching the developer's keys.
SETUP_TEST_BIN="$TEST_ROOT/setup-bin"
SETUP_HOME="$TEST_ROOT/setup-home"
mkdir -p "$SETUP_TEST_BIN" "$SETUP_HOME"
# shellcheck disable=SC2016 # Generated stub expressions expand at runtime.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  auth)' \
  '    [[ ${2:-} == status ]] && exit 1' \
  '    [[ ${2:-} == login ]] && { cat > /dev/null; exit 0; }' \
  '    exit 0' \
  '    ;;' \
  '  api | ssh-key | gpg-key) exit 0 ;;' \
  'esac' \
  'exit 0' > "$SETUP_TEST_BIN/gh"
chmod +x "$SETUP_TEST_BIN/gh"
# shellcheck disable=SC2016 # Generated stub expressions expand at runtime.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'key_file=""' \
  'while (($# > 0)); do' \
  '  if [[ $1 == -f ]]; then key_file=$2; shift 2; else shift; fi' \
  'done' \
  'mkdir -p "$(dirname "$key_file")"' \
  ': > "$key_file"' \
  ': > "$key_file.pub"' > "$SETUP_TEST_BIN/ssh-keygen"
chmod +x "$SETUP_TEST_BIN/ssh-keygen"
# shellcheck disable=SC2016 # Generated stub expressions expand at runtime.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in' \
  '  --list-secret-keys) exit 1 ;;' \
  '  --armor) printf "stub-key\\n"; exit 0 ;;' \
  'esac' \
  'exit 0' > "$SETUP_TEST_BIN/gpg"
chmod +x "$SETUP_TEST_BIN/gpg"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SETUP_TEST_BIN/gpgconf"
chmod +x "$SETUP_TEST_BIN/gpgconf"
setup_success_status=0
printf 'token\n3\n' | NAME='Setup User' EMAIL='setup@example.test' \
  HOME="$SETUP_HOME" XDG_CONFIG_HOME="$SETUP_HOME/.config" \
  TERM=dumb PATH="$SETUP_TEST_BIN:$TEST_BIN:$PATH" \
  "$ROOT_DIR/runtime/scripts/setup" > "$TEST_ROOT/direct-setup-output" 2>&1 || setup_success_status=$?
((setup_success_status == 0)) || fail 'stubbed direct setup did not succeed'
require_file "$SETUP_HOME/.config/git/config"
require_file "$SETUP_HOME/.ssh/id_ed25519.pub"
require_output "$TEST_ROOT/direct-setup-output" 'Setup Complete'

DISPATCH_SETUP_HOME="$TEST_ROOT/dispatcher-setup-home"
mkdir -p "$DISPATCH_SETUP_HOME"
dispatcher_setup_status=0
printf 'token\n3\n' | NAME='Dispatcher Setup User' EMAIL='dispatcher@example.test' \
  HOME="$DISPATCH_SETUP_HOME" XDG_CONFIG_HOME="$DISPATCH_SETUP_HOME/.config" \
  TERM=dumb PATH="$SETUP_TEST_BIN:$TEST_BIN:$PATH" \
  "$GIT_SETUP" setup > "$TEST_ROOT/dispatcher-setup-output" 2>&1 || dispatcher_setup_status=$?
((dispatcher_setup_status == 0)) || fail 'dispatcher setup command did not succeed with stubs'
require_file "$DISPATCH_SETUP_HOME/.config/git/config"

# Short and option aliases must resolve through the same public dispatcher.
run_setup "$CUSTOM_HOME" -f > "$TEST_ROOT/config-alias-output"
require_output "$TEST_ROOT/config-alias-output" 'Git Configuration Files'
run_setup "$CUSTOM_HOME" -v > "$TEST_ROOT/verify-alias-output" || true
require_output "$TEST_ROOT/verify-alias-output" 'Generated Git Configuration Files'
run_setup "$CUSTOM_HOME" --help > "$TEST_ROOT/help-alias-output"
require_output "$TEST_ROOT/help-alias-output" 'GITHUB TOKEN'
alias_test_status=0
run_setup "$UNCONFIGURED_HOME" t > "$TEST_ROOT/test-alias-output" 2>&1 || alias_test_status=$?
((alias_test_status != 0)) || fail 'test alias unexpectedly succeeded without an identity'
require_output "$TEST_ROOT/test-alias-output" 'Git identity is not configured'
printf 'no\n' | run_setup "$CUSTOM_HOME" c > "$TEST_ROOT/clean-alias-output"
require_output "$TEST_ROOT/clean-alias-output" 'Cancelled'

# Every documented alias reaches its canonical command module. Help keeps
# these routing checks offline and side-effect free.
for alias in --config -f; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'Git Configuration Usage'
done
run_setup "$CUSTOM_HOME" f --help > "$TEST_ROOT/alias-help-output"
require_output "$TEST_ROOT/alias-help-output" 'Git Configuration Usage'
for alias in --verify -v; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'Git Verification Usage'
done
run_setup "$CUSTOM_HOME" v --help > "$TEST_ROOT/alias-help-output"
require_output "$TEST_ROOT/alias-help-output" 'Git Verification Usage'
for alias in s --setup -s; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'Git Setup Usage'
done
for alias in --test -t; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'Git Integration Test Usage'
done
for alias in --clean -c; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'Git Cleanup Usage'
done
for alias in h -h; do
  run_setup "$CUSTOM_HOME" "$alias" --help > "$TEST_ROOT/alias-help-output"
  require_output "$TEST_ROOT/alias-help-output" 'GITHUB TOKEN'
done

# Invoking without arguments remains the original interactive RaVN menu.
printf 'q\n' | run_setup "$CUSTOM_HOME" > "$TEST_ROOT/menu-output"
require_output "$TEST_ROOT/menu-output" 'Git + GitHub + GPG Configuration for Arch Linux'
require_output "$TEST_ROOT/menu-output" 'Choose an action'
require_output "$TEST_ROOT/menu-output" 'Verify current configuration'
require_output "$TEST_ROOT/menu-output" 'Help and usage'

# Help is available from both the direct command and the interactive menu.
run_setup "$CUSTOM_HOME" help > "$TEST_ROOT/help-output"
require_output "$TEST_ROOT/help-output" 'GITHUB TOKEN'
require_output "$TEST_ROOT/help-output" 'CONFIGURATION FILES'
require_output "$TEST_ROOT/help-output" 'config   Create or refresh the managed Git configuration files.'
require_output "$TEST_ROOT/help-output" 'verify   Review Git, SSH, GPG, GitHub, and generated configuration files.'

catalog_lookup_status=0
catalog_lookup_output=$(
  bash -c 'source "$1/runtime/lib/presentation.sh"; source "$1/runtime/lib/command_catalog.sh"; command_catalog_get missing label || printf "%s\n" "$GIT_SETUP_COMMAND_CATALOG_ERROR"' _ "$ROOT_DIR" 2>&1
) || catalog_lookup_status=$?
((catalog_lookup_status == 0)) || fail 'catalog lookup diagnostic command failed'
grep -Fq 'Unknown command: missing' <<< "$catalog_lookup_output" || fail 'catalog lookup failure was not descriptive'
printf 'h\n\nq\n' | run_setup "$CUSTOM_HOME" > "$TEST_ROOT/menu-help-output"
require_output "$TEST_ROOT/menu-help-output" 'RECOMMENDED FLOW'
[[ $(grep -Fc 'Choose an action' "$TEST_ROOT/menu-help-output") -eq 2 ]] || fail 'menu did not return after help'

# A failed verification in the interactive menu must still return to the menu
# after the user acknowledges the result.
printf '1\n\nq\n' | run_setup "$CUSTOM_HOME" > "$TEST_ROOT/menu-return-output"
[[ $(grep -Fc 'Choose an action' "$TEST_ROOT/menu-return-output") -eq 2 ]] || fail 'menu did not return after verification'

printf 'PASS: git-setup managed configuration and interactive workflow\n'
