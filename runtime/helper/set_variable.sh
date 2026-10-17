#!/usr/bin/env bash

# Shared repository, runtime, template, and generated-configuration paths.
helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly GIT_SETUP_RUNTIME_DIR="${GIT_SETUP_RUNTIME_DIR:-$(cd "$helper_dir/.." && pwd)}"
readonly GIT_SETUP_ROOT="${GIT_SETUP_ROOT:-$(cd "$GIT_SETUP_RUNTIME_DIR/.." && pwd)}"
readonly GIT_SETUP_LEGACY_ENTRYPOINT="$GIT_SETUP_ROOT/bin/git-setup"
readonly WORKFLOW_SOURCE_DIR="$GIT_SETUP_ROOT/make/workflow"
TEMPLATE_DIR="${TEMPLATE_DIR:-$GIT_SETUP_RUNTIME_DIR/templates/git}"
GIT_CONFIG_DIR="${GIT_CONFIG_DIR:-$HOME/.config/git}"
GIT_CONFIG_FILE="${GIT_CONFIG_FILE:-$GIT_CONFIG_DIR/config}"
GIT_SETUP_BIN_DIR="${GIT_SETUP_BIN_DIR:-${WORKFLOW_COMMAND_DIR:-$HOME/bin}}"
while [[ $GIT_SETUP_BIN_DIR == ?*/ ]]; do
  GIT_SETUP_BIN_DIR="${GIT_SETUP_BIN_DIR%/}"
done
WORKFLOW_COMMAND_DIR="$GIT_SETUP_BIN_DIR"
LEGACY_WORKFLOW_COMMAND_DIR="$HOME/.local/bin"
while [[ $LEGACY_WORKFLOW_COMMAND_DIR == ?*/ ]]; do
  LEGACY_WORKFLOW_COMMAND_DIR="${LEGACY_WORKFLOW_COMMAND_DIR%/}"
done
USER_NAME="${USER_NAME:-${NAME:-Roberto Flores}}"
USER_EMAIL="${USER_EMAIL:-${EMAIL:-25asab015@ujmd.edu.sv}}"

export GIT_SETUP_ROOT
export GIT_SETUP_RUNTIME_DIR
export GIT_SETUP_LEGACY_ENTRYPOINT
export WORKFLOW_SOURCE_DIR
export TEMPLATE_DIR
export GIT_CONFIG_DIR
export GIT_CONFIG_FILE
export GIT_SETUP_BIN_DIR
export WORKFLOW_COMMAND_DIR
export LEGACY_WORKFLOW_COMMAND_DIR
export USER_NAME
export USER_EMAIL
