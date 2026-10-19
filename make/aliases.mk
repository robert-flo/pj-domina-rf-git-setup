# ═══════════════════════════════════════════════════════════════
# 📎 COMPATIBILITY ALIASES
# ═══════════════════════════════════════════════════════════════
# 🎯 Purpose: Short redirects for the Git and Docker targets

.PHONY: help-aliases \
        git-a git-c git-ac git-p git-st git-s git-d git-ds git-l git-lg \
        git-af git-fuck git-bye git-df git-fc git-fm \
        a c ac p l st s d ds lg af fuck bye clean df fc fm cm db dr dc

help-aliases: ## Show Git compatibility aliases
	@printf "\n"
	@printf "$(CYAN)═════════════════════════════════════════════════════════════════════════════════\n$(NC)"
	@printf "$(CYAN)  📎 Compatibility Aliases\n$(NC)"
	@printf "$(CYAN)═════════════════════════════════════════════════════════════════════════════════\n$(NC)"
	@printf "\n"
	@printf "$(BLUE)%-20s %-25s %s$(NC)\n" "ALIAS" "TARGET" "DESCRIPTION"
	@printf "$(CYAN)%-20s %-25s %s$(NC)\n" "-----" "------" "-----------"
	@printf "%-20s %-25s %s\n" "a / git-a" "git-add" "Stage all changes"
	@printf "%-20s %-25s %s\n" "c / git-c" "git-commit" "Create a timestamped commit"
	@printf "%-20s %-25s %s\n" "cm" "git-cm MSG=..." "Commit with a custom message"
	@printf "%-20s %-25s %s\n" "ac / git-ac" "git-add-commit" "Stage and commit"
	@printf "%-20s %-25s %s\n" "p / git-p" "git-push" "Push the current branch"
	@printf "%-20s %-25s %s\n" "l / git-l" "git-pull" "Pull the current branch"
	@printf "%-20s %-25s %s\n" "st, s / git-st, git-s" "git-status" "Show repository state"
	@printf "%-20s %-25s %s\n" "d / git-d" "git-diff" "Show uncommitted changes"
	@printf "%-20s %-25s %s\n" "ds / git-ds" "git-status-diff" "Short status and diff"
	@printf "%-20s %-25s %s\n" "lg / git-lg" "git-log" "Show recent history"
	@printf "%-20s %-25s %s\n" "af / git-af" "git-add-fuzzy" "Interactively stage changes"
	@printf "%-20s %-25s %s\n" "fuck / git-fuck" "git-amend" "Amend the last commit"
	@printf "%-20s %-25s %s\n" "bye, clean / git-bye" "git-clean" "Remove merged worktrees"
	@printf "%-20s %-25s %s\n" "df / git-df" "git-diff-fuzzy" "Select a commit to inspect"
	@printf "%-20s %-25s %s\n" "fc / git-fc" "git-search CODE=..." "Search history by code"
	@printf "%-20s %-25s %s\n" "fm / git-fm" "git-search MSG=..." "Search history by message"
	@printf "%-20s %-25s %s\n" "db" "docker-build" "Build the local Docker image"
	@printf "%-20s %-25s %s\n" "dr" "docker-run" "Run the ephemeral Docker container"
	@printf "%-20s %-25s %s\n" "dc" "docker-clean" "Remove the local Docker image"
	@printf "\n"

# === Portable Git workflow adapters ===
# Keep this Make fragment portable: each target resolves its executable from
# the bundled workflow directory instead of requiring a prior git-setup install.
GIT_WORKFLOW_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))workflow/
workflow_quote = '$(subst ','"'"'",$(1))'
define run_workflow
	@WORKFLOW_ARGUMENT=$(call workflow_quote,$(2)) "$(GIT_WORKFLOW_DIR)$(1)"
endef

# === Git Operations (git-) ===
git-a: ; $(call run_workflow,a)
git-c: ; $(call run_workflow,c)
git-ac: ; $(call run_workflow,ac)
git-p: ; $(call run_workflow,p)
git-l: ; $(call run_workflow,l)
git-st: ; $(call run_workflow,st)
git-s: ; $(call run_workflow,s)
git-d: ; $(call run_workflow,d)
ds: ; $(call run_workflow,ds)
git-ds: ; $(call run_workflow,ds)
git-lg: ; $(call run_workflow,lg)
git-af: ; $(call run_workflow,af)
git-fuck: ; $(call run_workflow,fuck,$(MSG))
git-bye: ; $(call run_workflow,bye)
git-df: ; $(call run_workflow,df)
git-fc: ; $(call run_workflow,fc,$(CODE))
git-fm: ; $(call run_workflow,fm,$(MSG))

# === Short Git Aliases ===
a: ; $(call run_workflow,a)
c: ; $(call run_workflow,c)
cm: ; $(call run_workflow,cm,$(MSG))
ac: ; $(call run_workflow,ac)
p: ; $(call run_workflow,p)
l: ; $(call run_workflow,l)
st: ; $(call run_workflow,st)
s: ; $(call run_workflow,s)
d: ; $(call run_workflow,d)
lg: ; $(call run_workflow,lg)
af: ; $(call run_workflow,af)
fuck: ; $(call run_workflow,fuck,$(MSG))
bye: ; $(call run_workflow,bye)
clean: ; $(call run_workflow,clean)
df: ; $(call run_workflow,df)
fc: ; $(call run_workflow,fc,$(CODE))
fm: ; $(call run_workflow,fm,$(MSG))

# Short Docker aliases
db: docker-build
dr: docker-run
dc: docker-clean
