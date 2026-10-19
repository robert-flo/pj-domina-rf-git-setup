# ═══════════════════════════════════════════════════════════════
# 🔀 GIT OPERATIONS - Version control and backup
# ═══════════════════════════════════════════════════════════════
# 📚 Documentation: docs/make/git.md
# 🎯 Purpose: Stage, commit, push and inspect git repository state
# ──── Overview: 7 targets for the full git commit/push cycle ─
#
# 📎 Aliases & Targets:
#    Each short alias is also a managed direct command and Git alias after
#    git-setup config: `s`, `git s`, and `make s` share one workflow surface.
#    Input is positional (`cm "message"`, `fc "query"`); MSG and CODE remain
#    Make compatibility variables. Use DRY_RUN=1 to preview mutating commands.
#    Managed short commands verify Git repository context before validating
#    input or running work; `s` and `st` report the missing context in place.
#    ALIAS          TARGET                   DESCRIPTION
#    a  / git-a     git-add                  Stage all changes
#    c  / git-c     git-commit               Quick timestamped commit
#    cm / git-cm    git-cm MSG="..."         Commit with custom message
#    ac / git-ac    git-add-commit           Stage & commit together
#    p  / git-p     git-push                 Push commits to remote
#    l  / git-l     git-pull                 Pull remote changes
#    st / git-st    git-status               Show repository state
#    s  / git-s     git-status               Show repository state
#    d  / git-d     git-diff                 Show uncommitted diffs
#    ds / git-ds    git-status-diff          Short status + diff
#    lg / git-lg    git-log                  Show commit log history
#    af / git-af    git-add-fuzzy            Interactively stage (fzf)
#    fuck/git-fuck  git-amend                Amend last commit (MSG="...")
#    clean          git-clean                Review and remove merged worktrees
#    df / git-df    git-diff-fuzzy           Fuzzy select commit to diff
#    fc / git-fc    git-search CODE="..."    Search history by code modification
#    fm / git-fm    git-search MSG="..."     Search history by message query
#
# 🧪 Dry Run (preview without executing):
#    make git-add             DRY_RUN=1   · skip git add
#    make git-commit          DRY_RUN=1   · skip git commit
#    make git-push            DRY_RUN=1   · skip git push
#    make git-pull            DRY_RUN=1   · skip git pull
#    make git-amend           DRY_RUN=1   · skip git commit --amend
#    make git-clean            DRY_RUN=1   · preview cleanup without removing
#    make git-protect-default-branch DRY_RUN=1 · preview GitHub branch protection
#    (git-status, git-diff, git-log, git-add-fuzzy, git-diff-fuzzy, git-search are read-only)

DRY_RUN ?= 0
export DRY_RUN
ifeq ($(DRY_RUN),1)
  EXEC = echo "  ▶ [dry-run]"
else
  EXEC =
endif

# Intercept positional workflow arguments so Make shares the direct and Git
# command contract. MSG and CODE remain supported as compatibility variables.
WORKFLOW_GOAL := $(firstword $(MAKECMDGOALS))
WORKFLOW_ARGUMENT := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ifneq ($(filter $(WORKFLOW_GOAL),git-cm cm git-amend fuck fc fm),)
  ifneq ($(filter $(WORKFLOW_GOAL),fc),)
    CODE ?= $(WORKFLOW_ARGUMENT)
  else ifneq ($(filter $(WORKFLOW_GOAL),fm),)
    MSG ?= $(WORKFLOW_ARGUMENT)
  else
    MSG ?= $(WORKFLOW_ARGUMENT)
  endif
  # Avoid erroring out on positional arguments treated as targets.
  %:
	@:
endif

RAVN_WTS_DIR ?= $(abspath $(RAVN_DIR)/..)
GIT_REMOTE ?= origin
BASE_BRANCH ?= master
PROTECTED_BRANCHES ?= master dev rc imgbot
GIT_PROTECTION_REQUIRED_APPROVALS ?= 0

# Keep every workflow footer in the same three-column teaching layout.
define WORKFLOW_QUICK_ACTION
	@printf "  • %-20s $(BLUE)%-5s$(NC) · $(BLUE)%-10s$(NC) · $(BLUE)%s$(NC)\n" "$(1):" "$(2)" "git $(2)" "make $(2)"
endef

.PHONY: help-git git-add git-commit git-cm git-add-commit git-push git-pull git-status git-diff git-log git-setup git-sync git-diff-dev git-diff-rc git-diff-here \
        git-add-fuzzy git-amend git-clean git-prune-branches git-diff-fuzzy git-search git-protect-default-branch

# ═══════════════════════════════════════════════════════════════
# 🔀 HELP-GIT - Show Git operations
# ═══════════════════════════════════════════════════════════════
help-git: ## Show Git operation targets
	@printf "\n"
	@printf "$(CYAN)Git operation targets$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  make git-add              Stage all changes\n"
	@printf "  make git-commit           Stage and create a timestamped commit\n"
	@printf "  make git-cm MSG=...       Stage and commit with a custom message\n"
	@printf "  make git-add-commit       Stage and commit in one step\n"
	@printf "  make git-push             Push the current branch\n"
	@printf "  make git-pull             Pull the current branch\n"
	@printf "  make git-status           Show repository state\n"
	@printf "  make git-diff             Show uncommitted changes\n"
	@printf "  make git-log              Show recent history\n"
	@printf "  make git-add-fuzzy        Select files to stage\n"
	@printf "  make git-amend            Amend the last commit\n"
	@printf "  make git-clean             Review and remove merged worktrees/branches\n"
	@printf "  make git-diff-fuzzy       Select a commit to inspect\n"
	@printf "  make git-search           Search history by CODE or MSG\n"
	@printf "  make git-setup            Create a bare clone and worktrees\n"
	@printf "  make git-sync             Rebase topic worktrees onto origin/master\n"
	@printf "  make git-diff-here        Compare the worktree with the base branch\n"
	@printf "  make git-protect-default-branch\n"
	@printf "                            Require PRs before updating the GitHub default branch\n"
	@printf "\nRun make help-aliases for compatibility aliases. Set DRY_RUN=1 to preview mutating targets.\n"

# ═══════════════════════════════════════════════════════════════
# 🛡️  GIT-PROTECT-DEFAULT-BRANCH - Require pull requests on GitHub
# ═══════════════════════════════════════════════════════════════
# ──── Protection: Resolves the current GitHub repo and its default branch ────
# ──── Usage: make git-protect-default-branch [GIT_PROTECTION_REQUIRED_APPROVALS=1] ────
git-protect-default-branch: ## Require PRs before updating the GitHub default branch
	@set -eu; \
	if ! command -v gh > /dev/null 2>&1; then \
		printf "$(RED)  ✗ GitHub CLI (gh) is required$(NC)\n"; \
		exit 1; \
	fi; \
	if ! gh auth status > /dev/null 2>&1; then \
		printf "$(RED)  ✗ authenticate GitHub CLI first: gh auth login$(NC)\n"; \
		exit 1; \
	fi; \
	case "$(GIT_PROTECTION_REQUIRED_APPROVALS)" in \
		'' | *[!0-9]*) \
			printf "$(RED)  ✗ GIT_PROTECTION_REQUIRED_APPROVALS must be a non-negative integer$(NC)\n"; \
			exit 1 ;; \
	esac; \
	REPOSITORY=$$(gh repo view --json nameWithOwner --jq '.nameWithOwner') || exit 1; \
	DEFAULT_BRANCH=$$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name') || exit 1; \
	if [ -z "$$REPOSITORY" ] || [ -z "$$DEFAULT_BRANCH" ] || [ "$$REPOSITORY" = "null" ] || [ "$$DEFAULT_BRANCH" = "null" ]; then \
		printf "$(RED)  ✗ could not resolve a GitHub repository and default branch$(NC)\n"; \
		exit 1; \
	fi; \
	PAYLOAD=$$(printf '%s' '{"required_status_checks":null,"enforce_admins":true,"required_pull_request_reviews":{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,"required_approving_review_count":$(GIT_PROTECTION_REQUIRED_APPROVALS),"require_last_push_approval":false},"restrictions":null,"required_linear_history":false,"allow_force_pushes":false,"allow_deletions":false,"block_creations":false,"required_conversation_resolution":false,"lock_branch":false,"allow_fork_syncing":false}'); \
	printf "  $(DIM)repository:$(NC) $$REPOSITORY\n"; \
	printf "  $(DIM)branch:$(NC)     $$DEFAULT_BRANCH\n"; \
	printf "  $(DIM)approvals:$(NC)  $(GIT_PROTECTION_REQUIRED_APPROVALS)\n"; \
	if [ "$(DRY_RUN)" = "1" ]; then \
		printf "\n  ▶ [dry-run] would require pull requests and block direct/force pushes\n"; \
		exit 0; \
	fi; \
	printf '%s\n' "$$PAYLOAD" | gh api --method PUT \
		"repos/$$REPOSITORY/branches/$$DEFAULT_BRANCH/protection" --input - > /dev/null; \
	printf "\n$(GREEN)  ✓ protected $$DEFAULT_BRANCH: updates now require a pull request$(NC)\n\n"; \
	printf "  $(DIM)Administrators cannot bypass the rule; force-pushes and deletion are blocked.\n$(NC)"

# ═══════════════════════════════════════════════════════════════
# 💾 GIT-ADD - Stage all modified/new files for commit
# ═══════════════════════════════════════════════════════════════
# ──── Stage: Adds all modified/new files to the git index ────
git-add: ## Stage all changes for git
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)💾 git-add · staging all changes$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@CHANGED=$$(git status --short | wc -l); \
	if [ $$CHANGED -gt 0 ]; then \
		printf "  adding $$CHANGED file(s) to staging area...\n"; \
		$(EXEC) git add .; \
		printf "$(GREEN)  ✓ staged $$CHANGED file(s)$(NC)\n\n"; \
		git status --short | sed 's/^/  /'; \
	else \
		printf "$(GREEN)  ✓  nothing to stage — working tree is clean$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,commit staged changes,c)
	$(call WORKFLOW_QUICK_ACTION,stage and commit,ac)
	$(call WORKFLOW_QUICK_ACTION,inspect changes,d)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📝 GIT-COMMIT - Create a timestamped commit from staged changes
# ═══════════════════════════════════════════════════════════════
# ──── Commit: Stages all and creates commit with timestamp ───
git-commit: ## Quick commit with timestamp
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📝 git-commit · timestamped snapshot$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if [ -n "$$(git status --porcelain)" ]; then \
		printf "  staging changes...\n"; \
		$(EXEC) git add .; \
		COMMIT_MSG="config: update $$(date '+%Y-%m-%d %H:%M:%S')"; \
		printf "  commit: $(GREEN)$$COMMIT_MSG$(NC)\n\n"; \
		$(EXEC) git commit --signoff -m "$$COMMIT_MSG" || exit 1; \
		COMMIT_HASH=$$(git rev-parse --short HEAD); \
		BRANCH=$$(git branch --show-current); \
		printf "$(GREEN)  ✓ $(NC)$(DIM)$$COMMIT_HASH$(NC)  $$BRANCH\n"; \
	else \
		printf "$(GREEN)  ✓  nothing to commit — working tree is clean$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,push to remote,p)
	$(call WORKFLOW_QUICK_ACTION,view history,lg)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📝 GIT-CM - Create a commit from staged changes with a custom message
# ═══════════════════════════════════════════════════════════════
# ──── Commit: Stages all and creates commit with custom message ─
git-cm: ## Commit with custom message (use MSG="message")
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📝 git-cm · custom commit$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if [ -z "$(MSG)" ]; then \
		printf "$(RED)  ✗ please specify MSG=\"message\" to commit$(NC)\n"; \
		printf "  example: $(BLUE)make git-cm MSG=\"your commit message\"$(NC)\n\n"; \
		exit 1; \
	fi
	@if [ -n "$$(git status --porcelain)" ]; then \
		printf "  staging changes...\n"; \
		$(EXEC) git add .; \
		printf "  commit: $(GREEN)$(MSG)$(NC)\n\n"; \
		$(EXEC) git commit --signoff -m "$(MSG)" || exit 1; \
		COMMIT_HASH=$$(git rev-parse --short HEAD); \
		BRANCH=$$(git branch --show-current); \
		printf "$(GREEN)  ✓ $(NC)$(DIM)$$COMMIT_HASH$(NC)  $$BRANCH\n"; \
	else \
		printf "$(GREEN)  ✓  nothing to commit — working tree is clean$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,push to remote,p)
	$(call WORKFLOW_QUICK_ACTION,view history,lg)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔗 GIT-ADD-COMMIT - Stage and commit all changes in one step
# ═══════════════════════════════════════════════════════════════
# ──── Composite: Calls git-add then git-commit with EMBEDDED=1 ─
git-add-commit: ## Stage and commit all changes together
	@$(MAKE) -s git-add EMBEDDED=1
	@$(MAKE) -s git-commit EMBEDDED=1
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,push to remote,p)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	$(call WORKFLOW_QUICK_ACTION,view history,lg)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# ☁️  GIT-PUSH - Sync local commits to remote repository
# ═══════════════════════════════════════════════════════════════
# ──── Push: Sends unpushed commits to origin via git push ────
git-push: ## Push to remote
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)☁️  git-push · sync to remote$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@BRANCH=$$(git branch --show-current); \
	REMOTE=$$(git remote get-url $(GIT_REMOTE) 2>/dev/null | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$$|\1|' | sed 's|\.git$$||'); \
	printf "  $(DIM)branch:$(NC) $$BRANCH  $(DIM)remote:$(NC) $$REMOTE\n"; \
	if git rev-parse --verify --quiet refs/remotes/$(GIT_REMOTE)/$$BRANCH >/dev/null 2>&1; then \
		UNPUSHED=$$(git log $(GIT_REMOTE)/$$BRANCH..HEAD --oneline 2>/dev/null | wc -l); \
		if [ $$UNPUSHED -gt 0 ]; then \
			printf "\n  pushing $$UNPUSHED commit(s)...\n"; \
			$(EXEC) git push || exit 1; \
			printf "$(GREEN)  ✓ pushed to remote$(NC)\n"; \
		else \
			printf "$(GREEN)  ✓  everything up-to-date$(NC)\n"; \
		fi; \
	else \
		printf "\n  pushing new branch $$BRANCH to remote...\n"; \
		$(EXEC) git push --set-upstream $(GIT_REMOTE) "$$BRANCH" || exit 1; \
		printf "$(GREEN)  ✓ pushed to remote$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,verify remote history,lg)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# ☁️  GIT-PULL - Pull updates from remote repository
# ═══════════════════════════════════════════════════════════════
# ──── Pull: Fetches and integrates remote changes ────────────
git-pull: ## Pull updates from remote
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)☁️  git-pull · pull from remote$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@BRANCH=$$(git branch --show-current); \
	REMOTE=$$(git remote get-url $(GIT_REMOTE) 2>/dev/null | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$$|\1|' | sed 's|\.git$$||'); \
	printf "  $(DIM)branch:$(NC) $$BRANCH  $(DIM)remote:$(NC) $$REMOTE\n\n"; \
	printf "  pulling changes from remote...\n\n"; \
	$(EXEC) git pull $(GIT_REMOTE) "$$BRANCH" || exit 1; \
	if [ "$$DRY_RUN" != "1" ]; then printf "\n$(GREEN)  ✓ pulled from remote$(NC)\n"; fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	$(call WORKFLOW_QUICK_ACTION,view history,lg)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📊 GIT-STATUS - Show repository state and recent commits
# ═══════════════════════════════════════════════════════════════
# ──── Status: Branch, remote, local changes, last 3 commits ─
git-status: ## Show current repository state
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📊 git-status · repository overview$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git rev-parse --git-dir > /dev/null 2>&1; then \
		REMOTE_URL=$$(git remote get-url $(GIT_REMOTE) 2>/dev/null); \
		REPO_NAME=$$(echo "$$REMOTE_URL" | sed -E 's|.*github.com[:/]([^/]+/[^/]+)(\.git)?$$|\1|' | sed 's|\.git$$||'); \
		BRANCH=$$(git branch --show-current); \
		AHEAD=$$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0); \
		BEHIND=$$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0); \
		STAGED=$$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' '); \
		UNSTAGED=$$(git diff --name-only 2>/dev/null | wc -l | tr -d ' '); \
		UNTRACKED=$$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' '); \
		GIT_DIR=$$(realpath "$$(git rev-parse --git-dir 2>/dev/null)"); \
		COMMON_DIR=$$(realpath "$$(git rev-parse --git-common-dir 2>/dev/null)"); \
		if [ "$$GIT_DIR" != "$$COMMON_DIR" ]; then WORKTREE="yes"; else WORKTREE="no"; fi; \
		printf "  $(DIM)repo:$(NC)      $$REPO_NAME\n"; \
		printf "  $(DIM)branch:$(NC)    $$BRANCH"; \
		if [ "$$AHEAD" -gt 0 ] && [ "$$BEHIND" -gt 0 ]; then \
			printf "  $(YELLOW)⇕ ↑$$AHEAD ↓$$BEHIND$(NC)"; \
		elif [ "$$AHEAD" -gt 0 ]; then \
			printf "  $(YELLOW)↑ $$AHEAD ahead$(NC)"; \
		elif [ "$$BEHIND" -gt 0 ]; then \
			printf "  $(RED)↓ $$BEHIND behind$(NC)"; \
		fi; \
		printf "\n"; \
		printf "  $(DIM)path:$(NC)      $(PWD)\n"; \
		printf "  $(DIM)worktree:$(NC)  $$WORKTREE\n\n"; \
		if [ "$$STAGED" -eq 0 ] && [ "$$UNSTAGED" -eq 0 ] && [ "$$UNTRACKED" -eq 0 ]; then \
			printf "  $(GREEN)✓ nothing to commit — working tree clean$(NC)\n"; \
			printf "\n"; \
		else \
			if [ "$$STAGED" -gt 0 ]; then \
				printf "  $(GREEN)staged:$(NC)    $$STAGED file(s)\n"; \
				git diff --cached --name-only 2>/dev/null | while IFS= read -r f; do printf "    $(GREEN)+$(NC) $$f\n"; done; \
				printf "\n"; \
			fi; \
			if [ "$$UNSTAGED" -gt 0 ]; then \
				printf "  $(YELLOW)modified:$(NC)  $$UNSTAGED file(s)\n"; \
				git diff --name-only 2>/dev/null | while IFS= read -r f; do printf "    $(YELLOW)~$(NC) $$f\n"; done; \
				printf "\n"; \
			fi; \
			if [ "$$UNTRACKED" -gt 0 ]; then \
				printf "  $(DIM)untracked:$(NC) $$UNTRACKED file(s)\n"; \
				git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do printf "    $(DIM)?$(NC) $$f\n"; done; \
				printf "\n"; \
			fi; \
		fi; \
		printf "  $(DIM)recent commits:$(NC)\n"; \
		git --no-pager log --max-count=5 --pretty=format:"  %C(green)%h%C(reset)  %<(50,trunc)%s  %C(dim)%<(15)%ar%C(reset)" 2>/dev/null; \
		printf "\n"; \
	else \
		printf "$(YELLOW)  ⚠  not a git repository$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,stage and commit,ac)
	$(call WORKFLOW_QUICK_ACTION,push changes,p)
	$(call WORKFLOW_QUICK_ACTION,full history,lg)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔄 GIT-DIFF - Show uncommitted changes in the repository
# ═══════════════════════════════════════════════════════════════
# ──── Diff: All repository files — summary and full detail ────
git-diff: ## Show uncommitted changes in the repository
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔄 git-diff · repository changes$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git diff --quiet 2>/dev/null; then \
		printf "$(GREEN)  ✓ no uncommitted changes in repository$(NC)\n"; \
	else \
		if command -v hunk >/dev/null 2>&1; then \
			hunk diff; \
		else \
			git diff --color=always 2>/dev/null || git diff; \
		fi; \
		printf "\n"; \
		CHANGED_FILES=$$(git diff --name-only 2>/dev/null | wc -l); \
		ADDED_LINES=$$(git diff --numstat 2>/dev/null | awk '{sum+=$$1} END {print sum+0}'); \
		DELETED_LINES=$$(git diff --numstat 2>/dev/null | awk '{sum+=$$2} END {print sum+0}'); \
		printf "  $(DIM)files:$(NC) $$CHANGED_FILES  $(GREEN)+$$ADDED_LINES$(NC)  $(RED)-$$DELETED_LINES$(NC)\n\n"; \
		git --no-pager diff --stat --color=always 2>/dev/null || git --no-pager diff --stat; \
		printf "\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,stage and commit,ac)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📜 GIT-LOG - Show recent commit history
# ═══════════════════════════════════════════════════════════════
# ──── Log: Last 15 commits — short hash, message, age ────────
git-log: ## Show recent commit history
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📜 git-log · recent history$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git rev-parse --git-dir > /dev/null 2>&1; then \
		git --no-pager log --max-count=15 --pretty=format:"  %C(green)%h%C(reset)  %<(58,trunc)%s  %C(dim)%<(15)%ar%C(reset)" 2>/dev/null; \
	else \
		printf "$(YELLOW)  ⚠  not a git repository$(NC)\n"; \
	fi
	@printf "\n"

# ═══════════════════════════════════════════════════════════════
# 🚀 GIT-SETUP - Clone a repo and create all worktrees ready to push
# ═══════════════════════════════════════════════════════════════
# ──── Setup: bare clone + all worktrees + upstream tracking ──
# ──── Usage: make git-setup REPO=git@github.com:user/repo.git ─
#
# Locations (can be overridden via environment variables):
#   Bare objects:  $$BARE_HOME/<repo>       (default: ~/.local/share/git-bare/<repo>)
#   Worktrees:     $$WORKTREES_HOME/<repo>  (default: ~/Work/<repo>)
git-setup: ## Clone a repo as bare + create all worktrees with upstream (use REPO=url)
	@printf "\n"
	@printf "$(CYAN)🚀 git-setup · bare clone + worktrees$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@if [ -z "$(REPO)" ] || [ "$(REPO)" = "RaVN" ]; then \
		printf "$(RED)  ✗ missing or invalid required argument$(NC)\n\n"; \
		printf "  usage:  $(BLUE)make git-setup REPO=git@github.com:robert-flo/RaVN.git$(NC)\n\n"; \
		printf "  override locations:\n"; \
		printf "    $(DIM)BARE_HOME$(NC)       bare objects dir   (default: $(DIM)~/.local/share/git-bare$(NC))\n"; \
		printf "    $(DIM)WORKTREES_HOME$(NC)  worktrees base dir (default: $(DIM)~/Work$(NC))\n\n"; \
		exit 1; \
	fi; \
	REPO_NAME=$$(basename "$(REPO)" .git); \
	BARE_DIR=$${BARE_HOME:-$$HOME/.local/share/git-bare}/$$REPO_NAME; \
	WORKTREE_DIR=$${WORKTREES_HOME:-$$HOME/Work}/$$REPO_NAME; \
	if [ -d "$$BARE_DIR" ] && [ -d "$$WORKTREE_DIR" ] && \
	   [ -f "$$WORKTREE_DIR/.git" ] && \
	   git --git-dir="$$BARE_DIR" worktree list >/dev/null 2>&1; then \
		printf "$(GREEN)  ✓ repository already configured$(NC)\n"; \
		printf "  $(DIM)Bare:$(NC)      $$BARE_DIR\n"; \
		printf "  $(DIM)Worktrees:$(NC) $$WORKTREE_DIR\n"; \
	else \
	if command -v git-bare-clone >/dev/null 2>&1; then \
		SCRIPT="git-bare-clone"; \
	elif [ -f "Configs/.local/bin/git-bare-clone" ]; then \
		SCRIPT="./Configs/.local/bin/git-bare-clone"; \
	else \
		SCRIPT=""; \
	fi; \
	if [ -z "$$SCRIPT" ]; then \
		printf "$(RED)  ✗ git-bare-clone not found$(NC)\n\n"; \
		printf "  It should be present at Configs/.local/bin/git-bare-clone\n"; \
		printf "  Ensure the file exists and is executable.\n\n"; \
		exit 1; \
	fi; \
	if [ "$$DRY_RUN" = "1" ]; then \
		printf "  ▶ [dry-run] $$SCRIPT $(REPO)\n"; \
	else \
		$$SCRIPT $(REPO); \
	fi; \
	fi
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@REPO_NAME=$$(basename "$(REPO)" .git); \
	WTHOME=$${WORKTREES_HOME:-$$HOME/Work}; \
	printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"; \
	printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"; \
	printf "  • enter a worktree:  $(BLUE)cd $$WTHOME/$$REPO_NAME/<branch>$(NC)\n"; \
	printf "  • check git status:  $(BLUE)make git-status$(NC)\n\n"

# ═══════════════════════════════════════════════════════════════
# 🔄 GIT-SYNC - Rebase all topic branches from the base branch
# ═══════════════════════════════════════════════════════════════
# ──── Sync: rebase each branch from origin/master by default ──
# ──── Usage: make git-sync [REPO=name] ────────────────────────
#
# Branches synced: Dynamically detected from ~/Work/<repo>/
# Branches EXCLUDED: protected/base branches and active non-topic branches
#
# Override worktrees location:
#   WORKTREES_HOME=~/Projects make git-sync REPO=RaVN
REPO ?= RaVN
git-sync: ## Rebase all topic branches from origin/master (local only)
	@printf "\n"
	@printf "$(CYAN)🔄 git-sync · update topic branches from $(GIT_REMOTE)/$(BASE_BRANCH)$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@if [ -z "$(REPO)" ]; then \
		printf "$(RED)  ✗ missing required argument$(NC)\n\n"; \
		printf "  usage:  $(BLUE)make git-sync REPO=RaVN$(NC)\n\n"; \
		printf "  override location:\n"; \
		printf "    $(DIM)WORKTREES_HOME$(NC)  worktrees base dir (default: $(DIM)~/Work$(NC))\n\n"; \
		exit 1; \
	fi
	@WTHOME=$${WORKTREES_HOME:-$$HOME/Work}; \
	REPO_DIR="$$WTHOME/$(REPO)"; \
	if [ ! -d "$$REPO_DIR" ]; then \
		printf "$(RED)  ✗ worktrees directory not found$(NC)\n\n"; \
		printf "  looked in:  $(DIM)$$REPO_DIR$(NC)\n\n"; \
		if [ -n "$$WORKTREES_HOME" ]; then \
			printf "  $(YELLOW)WORKTREES_HOME$(NC) is set to $(DIM)$$WORKTREES_HOME$(NC)\n"; \
			printf "  make sure $(BLUE)$(REPO)$(NC) worktrees exist there\n\n"; \
		else \
			printf "  $(DIM)WORKTREES_HOME$(NC) is not set — defaulting to $(DIM)~/Work$(NC)\n\n"; \
			printf "  if your worktrees are elsewhere, override:\n"; \
			printf "    $(BLUE)WORKTREES_HOME=<path> make git-sync REPO=$(REPO)$(NC)\n\n"; \
			printf "  if the repo is not cloned yet:\n"; \
			printf "    $(BLUE)make git-setup REPO=git@github.com:<user>/$(REPO).git$(NC)\n\n"; \
		fi; \
		exit 1; \
	fi; \
	FAILED=""; \
	for branch_dir in "$$REPO_DIR"/*; do \
		[ -d "$$branch_dir" ] || continue; \
		[ -e "$$branch_dir/.git" ] || continue; \
		branch=$$(basename "$$branch_dir"); \
		if printf '%s\n' $(PROTECTED_BRANCHES) | grep -Fxq "$$branch"; then \
			continue; \
		fi; \
		printf "  syncing $(BLUE)$$branch$(NC) ..."; \
		is_dirty=$$(git -C "$$branch_dir" status --porcelain 2>/dev/null); \
		err_log=$$(git -C "$$branch_dir" pull --rebase --autostash $(GIT_REMOTE) $(BASE_BRANCH) 2>&1); \
		if [ $$? -eq 0 ]; then \
			if [ -n "$$is_dirty" ]; then \
				printf " $(GREEN)✓$(NC) $(DIM)(autostashed)$(NC)\n"; \
			else \
				printf " $(GREEN)✓$(NC)\n"; \
			fi; \
		else \
			if echo "$$err_log" | grep -q "Conflict"; then \
				printf " $(RED)✗  rebase conflict$(NC)\n"; \
			else \
				printf " $(RED)✗  rebase failed: $$(echo "$$err_log" | head -n 1)$(NC)\n"; \
			fi; \
			git -C "$$branch_dir" rebase --abort > /dev/null 2>&1 || true; \
			FAILED="$$FAILED $$branch"; \
		fi; \
	done; \
	printf "\n$(DIM)  $(PROTECTED_BRANCHES): skipped (protected/base branches)$(NC)\n"; \
	if [ -n "$$FAILED" ]; then \
		printf "\n$(RED)  ✗ failed:$$FAILED$(NC)\n"; \
		printf "  resolve conflicts manually with:\n"; \
		for f in $$FAILED; do \
			printf "  $(BLUE)git -C $$REPO_DIR/$$f pull --rebase $(GIT_REMOTE) $(BASE_BRANCH)$(NC)\n"; \
		done; \
		printf "\n"; \
	else \
		printf "\n$(GREEN)  ✓ all branches synced locally$(NC)\n"; \
	fi
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • verify status: $(BLUE)make git-status$(NC)\n"
	@printf "  • view history:  $(BLUE)make git-log$(NC)\n\n"

# ═══════════════════════════════════════════════════════════════
# 🔄 GIT-DIFF-DEV - Compare dev worktree against rc worktree
# ═══════════════════════════════════════════════════════════════
# ──── Diff: Compare dev against rc using hunk patch ──────────
git-diff-dev: ## Compare dev branch against rc branch
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔄 git-diff-dev · compare dev against rc$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git show-ref --quiet refs/heads/rc && git show-ref --quiet refs/heads/dev; then \
		printf "  comparing dev against rc...\n"; \
		if command -v hunk >/dev/null 2>&1; then \
			git diff rc dev | hunk patch; \
		else \
			git diff --color=always rc dev 2>/dev/null || git diff rc dev; \
		fi; \
	else \
		printf "$(RED)  ✗ dev or rc branch not found$(NC)\n"; \
		exit 1; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • compare rc against master:            $(BLUE)make git-diff-rc$(NC)\n"
	@printf "  • compare current worktree against dev: $(BLUE)make git-diff-here$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔄 GIT-DIFF-RC - Compare rc branch against master branch
# ═══════════════════════════════════════════════════════════════
# ──── Diff: Compare rc against master using hunk patch ────────
git-diff-rc: ## Compare rc branch against master
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔄 git-diff-rc · compare rc against master$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git show-ref --quiet refs/heads/master && git show-ref --quiet refs/heads/rc; then \
		printf "  comparing rc against master...\n"; \
		if command -v hunk >/dev/null 2>&1; then \
			git diff master rc | hunk patch; \
		else \
			git diff --color=always master rc 2>/dev/null || git diff master rc; \
		fi; \
	else \
		printf "$(RED)  ✗ rc or master branch not found$(NC)\n"; \
		exit 1; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • compare dev against rc:               $(BLUE)make git-diff-dev$(NC)\n"
	@printf "  • compare current worktree against dev: $(BLUE)make git-diff-here$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔄 GIT-DIFF-HERE - Compare current branch/worktree against the base branch
# ═══════════════════════════════════════════════════════════════
# ──── Diff: Compare current worktree against master by default ─
git-diff-here: ## Compare current worktree against the base branch
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔄 git-diff-here · compare current worktree against $(BASE_BRANCH)$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if git show-ref --quiet refs/heads/$(BASE_BRANCH); then \
		printf "  comparing current worktree against $(BASE_BRANCH)...\n"; \
		if command -v hunk >/dev/null 2>&1; then \
			git diff $(BASE_BRANCH) | hunk patch; \
		else \
			git diff --color=always $(BASE_BRANCH) 2>/dev/null || git diff $(BASE_BRANCH); \
		fi; \
	else \
		printf "$(RED)  ✗ $(BASE_BRANCH) branch not found$(NC)\n"; \
		exit 1; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • compare dev against rc:    $(BLUE)make git-diff-dev$(NC)\n"
	@printf "  • compare rc against master: $(BLUE)make git-diff-rc$(NC)\n\n"
endif

# ═══════════════════════════════════════════════════════════════
# 💾 GIT-ADD-FUZZY - Interactively stage changes using fzf
# ═══════════════════════════════════════════════════════════════
# ──── Add Fuzzy: Interactive file staging with fzf ───────────
git-add-fuzzy: ## Interactively stage changes using fzf
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)💾 git-add-fuzzy · interactive staging$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if command -v fzf >/dev/null 2>&1; then \
		FILES=$$(git ls-files -m -o --exclude-standard | fzf -m --header="Select files to stage (TAB to multi-select, ENTER to accept)"); \
		if [ -n "$$FILES" ]; then \
			echo "$$FILES" | while IFS= read -r file; do \
				[ -n "$$file" ] && git add "$$file"; \
			done; \
			printf "$(GREEN)  ✓ staged selected file(s)$(NC)\n"; \
		else \
			printf "$(YELLOW)  ⚠  no files selected$(NC)\n"; \
		fi; \
	else \
		printf "$(RED)  ✗ fzf is not installed$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,commit staged changes,c)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 📝 GIT-AMEND - Modify last commit
# ═══════════════════════════════════════════════════════════════
# ──── Amend: Amends last commit message or staged files ──────
git-amend: ## Amend the last commit (use MSG="message" to update description)
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)📝 git-amend · modify last commit$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if [ -n "$(MSG)" ]; then \
		$(EXEC) git commit --signoff --amend -m "$(MSG)"; \
	else \
		$(EXEC) git commit --signoff --amend --no-edit; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,push changes to remote,p)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🧹 GIT-CLEAN - Review and optionally remove merged worktrees
# ═══════════════════════════════════════════════════════════════
# ──── Clean: report first, then ask before removing safe candidates ──
git-clean: ## Review and remove merged worktrees and branches
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🧹 git-clean · merged worktrees and branches$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@BASE=$$(git rev-parse --verify "$(BASE_BRANCH)" 2>/dev/null) || { printf "$(RED)  ✗ base branch not found: $(BASE_BRANCH)$(NC)\n"; exit 1; }; \
	TMP=$$(mktemp); trap 'rm -f "$$TMP"' EXIT; \
	printf "  $(DIM)base branch:$(NC) $(BASE_BRANCH)\n\n"; \
	printf "$(YELLOW)[1] Merged worktrees$(NC)\n"; \
	git worktree list --porcelain | awk '/^worktree /{path=$$2} /^branch refs\/heads\//{branch=$$2; sub("refs/heads/", "", branch); print branch "\t" path}' | \
	while IFS="	" read -r branch path; do \
		if printf '%s\n' $(PROTECTED_BRANCHES) | grep -Fxq "$$branch"; then continue; fi; \
		if git merge-base --is-ancestor "refs/heads/$$branch" "$$BASE"; then \
			if [ -n "$$(git -C "$$path" status --porcelain 2>/dev/null)" ]; then \
				printf "  $(RED)⚠ $$branch$(NC)  $$path  $(YELLOW)(modified; skipped)$(NC)\n"; \
			else \
				printf "  $(GREEN)✓ $$branch$(NC)  $$path  $(DIM)(clean; candidate)$(NC)\n"; \
				printf 'worktree\t%s\t%s\n' "$$branch" "$$path" >> "$$TMP"; \
			fi; \
		fi; \
	done; \
	printf "\n$(YELLOW)[2] Merged branches without worktrees$(NC)\n"; \
	ACTIVE=$$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p'); \
	git for-each-ref --merged "$$BASE" --format='%(refname:short)' refs/heads | \
	while IFS= read -r branch; do \
		if printf '%s\n' $(PROTECTED_BRANCHES) | grep -Fxq "$$branch" || printf '%s\n' "$$ACTIVE" | grep -Fxq "$$branch"; then continue; fi; \
		printf "  $(GREEN)✓ $$branch$(NC)  $(DIM)(branch only; candidate)$(NC)\n"; \
		printf 'branch\t%s\n' "$$branch" >> "$$TMP"; \
	done; \
	printf "\n$(YELLOW)[3] Protected branches$(NC)\n"; \
	printf "  $(DIM)%s$(NC)\n" "$(PROTECTED_BRANCHES)"; \
	COUNT=$$(wc -l < "$$TMP" | tr -d ' '); \
	if [ "$$COUNT" -eq 0 ]; then \
		printf "\n$(GREEN)  ✓ no safe cleanup candidates$(NC)\n"; \
	elif [ "$(DRY_RUN)" = "1" ]; then \
		printf "\n  ▶ [dry-run] $$COUNT candidate(s) reported; no changes made\n"; \
	else \
		printf "\n  Remove $$COUNT clean merged candidate(s)? [y/N] "; read -r answer; \
		case "$$answer" in y|Y|yes|YES) \
			while IFS="	" read -r kind branch path; do \
				if [ "$$kind" = "worktree" ]; then git worktree remove "$$path" && git branch -d "$$branch"; else git branch -d "$$branch"; fi; \
			done < "$$TMP"; \
			printf "$(GREEN)  ✓ cleanup completed$(NC)\n" ;; \
		*) printf "  cleanup cancelled; no changes made\n" ;; esac; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	@printf "  • %-20s $(BLUE)%-5s$(NC) · $(BLUE)%-10s$(NC) · $(BLUE)%s$(NC)\n\n" "review again:" "clean" "git bye" "make clean"
endif

git-prune-branches: git-clean

# ═══════════════════════════════════════════════════════════════
# 🔍 GIT-DIFF-FUZZY - Fuzzy select a past commit to diff
# ═══════════════════════════════════════════════════════════════
# ──── Diff Fuzzy: Interactively select a commit to diff ───────
git-diff-fuzzy: ## Fuzzy select a past commit to diff
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔍 git-diff-fuzzy · select commit to view diff$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if command -v fzf >/dev/null 2>&1; then \
		COMMIT=$$(git log --oneline --color=always | fzf --ansi --no-multi --header="Select commit to diff" | awk '{print $$1}'); \
		if [ -n "$$COMMIT" ]; then \
			git diff "$$COMMIT"^ "$$COMMIT"; \
		fi; \
	elif command -v peco >/dev/null 2>&1; then \
		COMMIT=$$(git log --oneline | peco | awk '{print $$1}'); \
		if [ -n "$$COMMIT" ]; then \
			git diff "$$COMMIT"^ "$$COMMIT"; \
		fi; \
	else \
		printf "$(RED)  ✗ neither fzf nor peco is installed$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	$(call WORKFLOW_QUICK_ACTION,view recent history,lg)
	@printf "\n"
endif

# ═══════════════════════════════════════════════════════════════
# 🔍 GIT-SEARCH - Search commit history
# ═══════════════════════════════════════════════════════════════
# ──── Search: Search history by message or source code changes ─
git-search: ## Search history (use CODE="string" or MSG="query")
ifndef EMBEDDED
	@printf "\n"
	@printf "$(CYAN)🔍 git-search · search commit history$(NC)\n"
	@printf "$(CYAN)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
endif
	@if [ -n "$(CODE)" ]; then \
		git log --pretty=format:"  %C(green)%h%C(reset)  %<(50,trunc)%s  %C(dim)%<(15)%ar%C(reset)" -S"$(CODE)"; \
		printf "\n"; \
	elif [ -n "$(MSG)" ]; then \
		git log --pretty=format:"  %C(green)%h%C(reset)  %<(50,trunc)%s  %C(dim)%<(15)%ar%C(reset)" --grep="$(MSG)"; \
		printf "\n"; \
	else \
		printf "$(RED)  ✗ please specify CODE=\"string\" or MSG=\"query\" to search$(NC)\n"; \
		printf "  example: $(BLUE)make git-search CODE=\"foo\"$(NC)\n"; \
		printf "  example: $(BLUE)make git-search MSG=\"chore\"$(NC)\n"; \
	fi
ifndef EMBEDDED
	@printf "\n$(GREEN)  ✓ done$(NC)\n"
	@printf "\n$(YELLOW)📋 Quick Actions:$(NC)\n"
	@printf "$(DIM)────────────────────────────────────────────────────────────────────────────────$(NC)\n"
	$(call WORKFLOW_QUICK_ACTION,view recent history,lg)
	$(call WORKFLOW_QUICK_ACTION,check repo state,s)
	@printf "\n"
endif
