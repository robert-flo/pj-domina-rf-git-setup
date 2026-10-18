# git-setup

An interactive Git, GitHub, SSH, and GPG configuration assistant for Linux.
`git-setup` creates a reproducible Git configuration under
`~/.config/git`, guides a complete setup from one terminal menu, and keeps
personal overrides separate from generated files.

---

<br>

<a id="installation"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=INSTALLATION" width="450"/>

### Linux Dependencies

The source workflow supports Arch Linux, Ubuntu/Debian, and Fedora. Install the
required commands for your distribution before starting `git-setup`:

```shell
# Arch Linux
sudo pacman -S --needed git github-cli gnupg openssh git-delta

# Ubuntu/Debian
sudo apt update && sudo apt install git gh gnupg openssh-client git-delta

# Fedora
sudo dnf install git gh gnupg2 openssh-clients git-delta
```

At startup, `git-setup` checks for `git`, `gh`, `gpg`, `ssh-keygen`, and
`delta`. If one is missing, it stops before changing configuration, recommends
the detected package manager first, and shows the equivalent commands for the
other supported Linux families. It never installs packages or runs privileged
commands for you.

### From Source

Clone the repository and start the interactive assistant:

```shell
git clone https://github.com/robert-flo/PJ-DOMINA-rf-git-setup.git
cd PJ-DOMINA-rf-git-setup
./git-setup
```

Choose **Run full setup** on the first run. It asks for your GitHub token,
name, and email; creates the managed Git files; configures SSH and GPG; and
lets you choose SSH, GPG, or no commit signing.

For automation, pass the identity without prompts:

```shell
NAME='Ada Lovelace' EMAIL='ada@example.com' ./git-setup config
```

---

<br>

<a id="github-token"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=GITHUB%20TOKEN" width="450"/>

Before running **Run full setup**, create a GitHub Personal Access Token and
save it in a password manager such as 1Password or Bitwarden.

`git-setup` uses this token to connect GitHub CLI with your account and add the
SSH, SSH-signing, and GPG public keys created during setup. Keep the token in
your password manager so you can reuse it whenever you configure a new machine.

See [how to create a GitHub token](docs/github-token.md) for the required
scopes and GitHub web steps.

---

<br>

<a id="docker"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=TRY%20IT%20IN%20DOCKER" width="450"/>

Run the assistant in an isolated Arch Linux container before using it with your
real home directory:

```shell
make docker-run
```

The default remains Arch Linux and builds `git-setup:local` when needed. You
can select Ubuntu or Fedora with `DOCKER_ENV`:

```shell
make docker-run DOCKER_ENV=ubuntu
make docker-run DOCKER_ENV=fedora
```

Each command starts an interactive, ephemeral container with no `$HOME` mount.
It is removed on exit, and the RaVN banner confirms this mode with
`󰡨 Running inside Docker`.

If you want to manage the local images explicitly:

```shell
make docker-build
make docker-clean
make docker-build DOCKER_ENV=ubuntu
make docker-clean DOCKER_ENV=ubuntu
make docker-clean-all
```

The Docker environment lets you try the complete setup flow before using your
real home directory. Use your saved token when prompted; SSH and GPG keys
created inside the container do not persist on your computer when it exits.
Their public keys are still added to GitHub as part of the complete setup flow.

---

<br>

<a id="commands"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=COMMANDS" width="450"/>

```shell
git-setup config    # generate ~/.config/git managed files
git-setup setup     # configure GitHub, SSH, GPG, and signing
git-setup verify    # audit the current configuration
git-setup test      # create and verify a signed test commit
git-setup clean     # remove the configuration after typing yes
```

Run `git-setup` without arguments to return to the interactive menu. The
integration test requires the Git name and email created by **Run full setup**;
otherwise it explains the prerequisite and does not offer a GitHub push.

## Shell Completion

The completion definitions use the same command metadata as the menu and help:

```shell
# Bash
source runtime/completion/git-setup.bash

# Zsh
fpath=(runtime/completion "$fpath[@]")
autoload -Uz compinit && compinit
```

Zsh discovers `_git-setup` from `runtime/completion`; Bash registers the
`git-setup` completion function when its file is sourced.

## Personal Git Customization

Generated files are refreshed by `git-setup config` and `git-setup setup`.
Use the optional file below for settings that must survive those refreshes:

```shell
nvim ~/.config/git/gitconfig.local
```

`gitconfig.local` is loaded last and is never generated, updated, or removed.

## Managed Git Workflow Commands

`git-setup config` also installs a managed workflow set in `~/.local/bin`.
Every operation has the same three workflow surfaces: a direct command, a Git
alias, and a portable Make alias. For example, these are equivalent:

```shell
s
git s
make s
```

The managed commands are `a`, `c`, `cm`, `ac`, `p`, `l`, `st`, `s`, `d`, `lg`,
`af`, `fuck`, `bye`, `clean`, `df`, `fc`, and `fm`. The Make companions live in
`make/workflow/` and travel with the repository fragment, so `make s` remains usable in a repository that
has not run `git-setup config`.

`clean` is the one Git-surface exception: Git's native `git clean` cannot be
overridden by an alias. Use `clean` or `make clean` for the managed safe cleanup
workflow, and `git bye` for its Git alias; `git clean` retains Git's native
behaviour.

Commands that accept input use the same positional form everywhere:

```shell
cm "docs: explain the workflow"
git cm "docs: explain the workflow"
make cm "docs: explain the workflow"

fc "workflow"
fm "docs"
fuck "fix: amend the previous commit"
```

`c` creates the existing timestamped commit; `cm` creates a commit with your
message. For Make compatibility, `MSG="..."` and `CODE="..."` continue to work
where they did before. Preview a mutating operation on any surface with
`DRY_RUN=1`, for example `DRY_RUN=1 ac`, `DRY_RUN=1 git ac`, or
`DRY_RUN=1 make ac`.

Every managed command verifies its Git repository context before validating
arguments or running an operation. Outside a repository, `s` and `st` retain
their repository overview with the `not a git repository` notice; every other
managed command shows the same notice and exits without performing work.

Running `git-setup config` refreshes these owned command files. Running
`git-setup clean` removes only them and its private runtime after confirmation;
it never removes `~/.local/bin` or unrelated commands. A personal or
repository-local Git alias may deliberately override a managed alias; `git-setup
verify` reports that condition.

---

<br>

<a id="security"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=SECURITY" width="450"/>

- GitHub tokens are read without echoing them to the terminal.
- GPG configuration is completed during **Run full setup**.
- Review token permissions before using **Run full setup**.
- `clean` requires an explicit `yes` before deleting local configuration.

---

<br>

<a id="contributing"></a>
<img src="https://readme-typing-svg.herokuapp.com?font=Lexend+Giga&size=25&pause=1000&color=CCA9DD&vCenter=true&width=435&height=25&lines=CONTRIBUTING" width="450"/>

- Prefer a clear, well-written issue describing a bug or feature over an
  unfocused pull request.
- Every change is reviewed line by line and should preserve the established
  RaVN terminal workflow.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for local checks and the pull-request
  workflow.

---

<br>

## License

This project is released under the [MIT License](LICENSE).
