# Changelog

All notable changes to this project are documented in this file.

## Unreleased

## [0.3.0] - 2026-08-01

### Fixed

- Fix false workflow-alias warnings and stale SSH agent sockets ([#50](https://github.com/robert-flo/git-setup/pull/50)). <!-- changelog-pr:50 -->


### Added

- Add Bash and Zsh completion from the command contract ([#48](https://github.com/robert-flo/git-setup/pull/48)). <!-- changelog-pr:48 -->

- Make menu metadata the source of truth ([#46](https://github.com/robert-flo/git-setup/pull/46)). <!-- changelog-pr:46 -->

- Introduce executable command dispatcher ([#42](https://github.com/robert-flo/git-setup/pull/42)). <!-- changelog-pr:42 -->


### Changed

- docs: specify executable command modularization ([#34](https://github.com/robert-flo/git-setup/pull/34)). <!-- changelog-pr:34 -->

- Separate shared runtime capabilities ([#45](https://github.com/robert-flo/git-setup/pull/45)). <!-- changelog-pr:45 -->

- Centralize runtime paths and relocate the private payload ([#44](https://github.com/robert-flo/git-setup/pull/44)). <!-- changelog-pr:44 -->

- Add self-describing command interfaces and dependency-independent help ([#43](https://github.com/robert-flo/git-setup/pull/43)). <!-- changelog-pr:43 -->

- fix: require repository context for workflow commands ([#32](https://github.com/robert-flo/git-setup/pull/32)). <!-- changelog-pr:32 -->


## [0.2.0] - 2026-07-31

### Added

- feat: add three-surface Git workflow commands ([#28](https://github.com/robert-flo/git-setup/pull/28)). <!-- changelog-pr:28 -->

- feat: protect default branch through make ([#23](https://github.com/robert-flo/git-setup/pull/23)). <!-- changelog-pr:23 -->


## [0.1.1] - 2026-07-20

### Added

- Selectable Docker environments from Make ([#21](https://github.com/robert-flo/git-setup/pull/21)). <!-- changelog-pr:21 -->


### Changed

- Package-manager-aware dependency guidance ([#19](https://github.com/robert-flo/git-setup/pull/19)). <!-- changelog-pr:19 -->
- Repository links now use the `git-setup` name.

### Fixed

- Clear an interactive terminal before startup output is printed.
