#!/usr/bin/env bash

# Git configuration generation capability shared by config and setup.

generate_git_config_files() {
  print_section "${RAVN_ICON[ui_gear]} Git Configuration Files"

  local -a generated_files=(
    "$GIT_CONFIG_FILE"
    "$GIT_CONFIG_DIR/delta.gitconfig"
    "$GIT_CONFIG_DIR/gitattributes.global"
    "$GIT_CONFIG_DIR/gitconfig_aliases"
    "$GIT_CONFIG_DIR/gitignore.global"
    "$GIT_CONFIG_DIR/shell_aliases"
  )
  local -a generated_actions=()
  local -a generated_descriptions=(
    "identity, signing and Git defaults"
    "delta themes and diff presentation"
    "global text and line-ending attributes"
    "Git command aliases"
    "global ignore patterns"
    "Git and GitHub shell shortcuts"
  )
  local file=""
  local template_file=""
  local index=0
  local line=""

  [[ -d $TEMPLATE_DIR ]] || {
    print_error "Missing configuration templates: $TEMPLATE_DIR"
    return 1
  }
  mkdir -p "$GIT_CONFIG_DIR"

  for file in "${generated_files[@]}"; do
    if [[ -e $file ]]; then
      generated_actions+=("Updated")
    else
      generated_actions+=("Created")
    fi
  done

  for index in "${!generated_files[@]}"; do
    file="${generated_files[$index]}"
    template_file="$TEMPLATE_DIR/${file##*/}"
    if [[ ${file##*/} == "config" ]]; then
      while IFS= read -r line || [[ -n $line ]]; do
        printf '%s\n' "${line//@CONFIG_DIR@/$GIT_CONFIG_DIR}"
      done < "$template_file" > "$file"
      git config --file "$file" user.name "$USER_NAME"
      git config --file "$file" user.email "$USER_EMAIL"
      # shellcheck disable=SC2088 # Git must receive a literal tilde here.
      git config --file "$file" user.signingkey "~/.ssh/id_ed25519.pub"
      git config --file "$file" gpg.format ssh
      git config --file "$file" commit.gpgsign true
      git config --file "$file" tag.gpgsign true
    else
      cp "$template_file" "$file"
    fi
  done

  chmod 0644 "${generated_files[@]}"

  print_info "Configuration directory: ${WHITE}$GIT_CONFIG_DIR${NC}"
  echo ""
  for index in "${!generated_files[@]}"; do
    print_success "${generated_actions[$index]}: ${WHITE}${generated_files[$index]}${NC}"
    echo -e "      ${GRAY}${generated_descriptions[$index]}${NC}"
  done

  echo ""
  print_info "Persistent Git customization: ${CYAN}nvim $GIT_CONFIG_DIR/gitconfig.local${NC}"
  echo -e "    ${GRAY}This optional file is loaded last and is never generated or overwritten.${NC}"

  echo ""
  print_info "Shell aliases: add ${CYAN}source $GIT_CONFIG_DIR/shell_aliases${NC} to ~/.zshrc"

  echo ""
  print_warn "Running 'git-setup config' or 'git-setup setup' rewrites the 6 generated files."

  echo ""
  print_info "To change their generated defaults, edit the templates in ${CYAN}$TEMPLATE_DIR${NC}."
  echo ""

  install_managed_workflow_commands
}

is_managed_workflow_file() {
  local file_path="$1"
  local workflow_file="${2:-${file_path##*/}}"

  [[ ! -L $file_path && -f $file_path ]] || return 1

  if [[ $workflow_file == ".git-workflow" ]]; then
    grep -Fq '# Managed workflow runtime.' "$file_path"
  else
    # shellcheck disable=SC2016 # Match the literal adapter exec expression.
    grep -Fq 'exec "$(dirname "$0")/.git-workflow"' "$file_path"
  fi
}

remove_legacy_workflow_leftovers() {
  local mode="${1:-config}"
  local -a workflow_files=(.git-workflow a c cm ac p l st s d lg af fuck bye clean df fc fm)
  local workflow_file=""
  local legacy_path=""
  local display_dir=""

  REMOVED_LEGACY_WORKFLOW_COMMANDS=0
  [[ -n ${LEGACY_WORKFLOW_COMMAND_DIR:-} && $WORKFLOW_COMMAND_DIR != "$LEGACY_WORKFLOW_COMMAND_DIR" ]] || return 0

  display_dir="${LEGACY_WORKFLOW_COMMAND_DIR/#$HOME/\~}"
  for workflow_file in "${workflow_files[@]}"; do
    legacy_path="$LEGACY_WORKFLOW_COMMAND_DIR/$workflow_file"
    [[ -e $legacy_path || -L $legacy_path ]] || continue
    if is_managed_workflow_file "$legacy_path" "$workflow_file"; then
      rm -f "$legacy_path"
      if [[ $mode == "clean" ]]; then
        print_success "Removed ${GRAY}${display_dir}/$workflow_file${NC}"
      else
        print_info "Removed legacy: ${GRAY}${display_dir}/$workflow_file${NC}"
      fi
      REMOVED_LEGACY_WORKFLOW_COMMANDS=$((REMOVED_LEGACY_WORKFLOW_COMMANDS + 1))
    else
      print_warn "kept unrelated ${display_dir}/$workflow_file"
    fi
  done
}

install_managed_workflow_commands() {
  # shellcheck disable=SC2153 # Value is provided by helper/set_variable.sh.
  local workflow_source_dir="$WORKFLOW_SOURCE_DIR"
  local -a workflow_files=(.git-workflow a c cm ac p l st s d lg af fuck bye clean df fc fm)
  local workflow_file=""
  local action=""

  [[ -d $workflow_source_dir ]] || {
    print_error "Missing portable workflow companions: $workflow_source_dir"
    return 1
  }
  mkdir -p "$WORKFLOW_COMMAND_DIR"

  print_section "${ICON_GIT} Managed Workflow Commands"
  for workflow_file in "${workflow_files[@]}"; do
    [[ -f $workflow_source_dir/$workflow_file ]] || {
      print_error "Missing portable workflow companion: $workflow_file"
      return 1
    }
    if [[ -e $WORKFLOW_COMMAND_DIR/$workflow_file ]]; then action="Updated"; else action="Created"; fi
    cp "$workflow_source_dir/$workflow_file" "$WORKFLOW_COMMAND_DIR/$workflow_file"
    chmod 0755 "$WORKFLOW_COMMAND_DIR/$workflow_file"
    print_success "$action: ${WHITE}$WORKFLOW_COMMAND_DIR/$workflow_file${NC}"
  done
  remove_legacy_workflow_leftovers config
  print_info "Commands: ${CYAN}s${NC}, ${CYAN}git s${NC}, and ${CYAN}make s${NC} share one workflow surface."
  echo ""
}
