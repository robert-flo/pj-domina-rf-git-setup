# git-setup Distribution

This context defines the terms used to distribute git-setup independently from
its source repository.

## Language

**Source repository**:
The repository that owns git-setup's executable, templates, tests, and release
versions.
_Avoid_: Package repository, installer repository

**Package repository**:
The separate Arch Linux packaging repository that builds and distributes a
released version of git-setup.
_Avoid_: Source repository, application repository

**Installed payload**:
The private executable, helpers, templates, and resources installed under
`/opt/git-setup` by the Arch package.
_Avoid_: User command, development checkout

**Runtime payload**:
The `runtime/` directory in the source repository that groups the private
helpers, libraries, executable command modules, and templates used by the root
launcher.
_Avoid_: User command, public repository surface

**Launcher**:
The small executable installed in `/usr/bin/git-setup` that delegates to the
installed payload.
_Avoid_: Installed payload, package repository

**Command module**:
An executable in `runtime/scripts/` that implements one git-setup operation and is
selected by the dispatcher, such as `config` or `verify`.
_Avoid_: Helper, launcher

**Release archive**:
The GitHub source tarball for a version tag that the Arch package verifies and
installs.
_Avoid_: Development checkout, live master branch

**Managed workflow command**:
The executable copy of a portable workflow companion installed in the user's
`~/bin` directory (or the directory configured by `GIT_SETUP_BIN_DIR`).
_Avoid_: Make alias, shell alias, Git subcommand

**Portable workflow companion**:
An executable in `make/workflow/` distributed with its Makefile fragment so repository
targets work without a prior git-setup installation.
_Avoid_: Configuration template, private helper

**Workflow surface**:
One of the equivalent ways to invoke a managed workflow command: directly from
`~/bin`, through `git <alias>`, or through `make <alias>`.
_Avoid_: Different command, alternative implementation

**Unified argument contract**:
The positional-argument syntax shared by every workflow surface. The Make
variables `MSG` and `CODE` remain compatibility inputs where they already exist.
_Avoid_: Make-only parameter syntax, Git-only parameter syntax

**Workflow dry run**:
The `DRY_RUN=1` environment contract that previews a mutating workflow command
without changing the repository, on every workflow surface.
_Avoid_: Make-only dry run, simulation flag

**Managed workflow set**:
The 17 Git workflow commands installed and removed as one owned set by
`git-setup`; Docker aliases are not members of this set.
_Avoid_: `~/bin` directory, `~/.local/bin` directory, all Make aliases

**Output parity**:
The requirement that a workflow companion preserves its corresponding
`make/git.mk` output exactly, except for documented intentional differences.
_Avoid_: Visual redesign, approximate compatibility

**Native Git command exception**:
An operation whose Git spelling is already a built-in subcommand and therefore
cannot be replaced by a Git alias. `clean` uses direct and Make surfaces while
`git bye` is its managed Git surface.
_Avoid_: Overridable Git alias, managed `git clean`
