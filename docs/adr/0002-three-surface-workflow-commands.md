# Use three equivalent workflow-command surfaces

Each short Git workflow command will be implemented by a portable companion in
`make/workflow/`, distributed with `make/git.mk`, and copied by `git-setup config` to
`~/bin` (originally `~/.local/bin`; see ADR 0003). The same operation will be
available as a direct command, a `git <alias>` shell alias, and a `make <alias>`
compatibility target. Command output will teach all three forms in its Quick
Actions, so Make remains usable in repositories that have not run git-setup
while the installed commands give one consistent workflow across repositories.

Commands that require input will accept it positionally on every surface (for
example, `cm "message"`, `git cm "message"`, and `make cm "message"`). Existing
Make `MSG` and `CODE` variables remain supported for compatibility. The README,
the command header, and `make/git.mk` will document each command's shared use.

Mutating commands will also preserve `DRY_RUN=1` as a shared environment
contract, allowing the same preview syntax before direct, Git-alias, and Make
invocations.

Each managed command establishes Git repository context before validating its
arguments or invoking an operation. `s` and `st` retain their informational
repository overview outside a repository; the other commands report the same
condition and exit without doing work.

`git-setup config` owns installation of the 17-command Git workflow set and
refreshes each executable. `git-setup clean` removes only those owned files
after confirmation; it never removes `~/bin`, `~/.local/bin`, unrelated user
commands, or Docker aliases.

The internal workflow module is a behaviour-preserving migration of
`make/git.mk`: tests must compare its output with the current target output in
controlled repository states. The only approved visual difference is that
Quick Actions show the direct, Git-alias, and Make forms of their next command.

`git clean` is a native Git command and cannot be overridden by an alias. The
managed cleanup operation therefore uses `clean` and `make clean`, with `git
bye` as its Git-alias surface; native `git clean` is preserved.
