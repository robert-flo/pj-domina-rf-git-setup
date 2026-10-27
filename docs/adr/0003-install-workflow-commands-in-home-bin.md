# Install managed workflow commands in ~/bin by default

`git-setup config` will install the managed workflow set (`a`, `c`, `cm`, `ac`,
`p`, `l`, `st`, `s`, `d`, `lg`, `af`, `fuck`, `bye`, `clean`, `df`, `fc`, `fm`,
and `.git-workflow`) into `~/bin` (`$HOME/bin`) by default instead of
`~/.local/bin`.

The target directory can be overridden with `GIT_SETUP_BIN_DIR`. For backward
compatibility, `WORKFLOW_COMMAND_DIR` remains accepted as a fallback alias when
`GIT_SETUP_BIN_DIR` is unset, and `GIT_SETUP_BIN_DIR` takes precedence when both
are set. The resolved path is normalized by stripping trailing slashes.

To prevent stale binaries from earlier installations in `~/.local/bin` from
shadowing the new location:

- `git-setup config` removes any legacy managed leftovers matching the 18
  managed names from `~/.local/bin` whenever the target install directory is not
  `~/.local/bin`, verifying that each file is a regular file with managed
  workflow content while preserving `~/.local/bin` itself, symlinks, and any
  unrelated user tools (with a warning).
- `git-setup clean` removes the 18 managed names from the configured install
  directory and any legacy managed leftovers from `~/.local/bin` after
  confirmation, never deleting either directory, symlinks, or unrelated files.
- `git-setup verify` checks the configured install directory and prints a
  `PATH` hint if `~/bin` (or `GIT_SETUP_BIN_DIR`) is missing from `PATH` or
  appears after `~/.local/bin`.
