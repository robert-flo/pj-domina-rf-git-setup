# Contributing to git-setup

Thank you for helping improve `git-setup`. Bug fixes, features,
documentation, and test improvements are all welcome.

## Getting started

1. Fork [the repository](https://github.com/robert-flo/pj-domina-rf-git-setup)
   and clone your fork:

   ```bash
   git clone https://github.com/<your-user>/pj-domina-rf-git-setup.git
   cd pj-domina-rf-git-setup
   ```

2. Create a focused branch from `master`:

   ```bash
   git switch -c type/short-description
   ```

3. Run the checks before opening a pull request:

   ```bash
   pre-commit run --all-files
   bash tests/git-setup.sh
   shellcheck git-setup runtime/helper/*.sh runtime/lib/*.sh runtime/scripts/* tests/*.sh
   ```

4. Commit atomically using the
   [commit message guidelines](COMMIT_MESSAGE_GUIDELINES.md), then push your
   branch and open a pull request targeting `master`.

## Guidelines

- Keep changes focused and preserve the established interactive RaVN workflow.
- Add or update a public-command regression test for behavior changes.
- Do not commit tokens, private keys, personal credentials, or local paths.
- Describe the validation you ran in the pull request.
- Follow the [branching and pull-request policy](RELEASE_POLICY.md): direct
  commits and pushes to `master` are not allowed.

## References

- [Pull request template](.github/PULL_REQUEST_TEMPLATE.md)
- [Commit message guidelines](COMMIT_MESSAGE_GUIDELINES.md)
- [Release policy](RELEASE_POLICY.md)
- [Project README](README.md)
