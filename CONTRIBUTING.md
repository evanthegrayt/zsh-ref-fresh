# Contributing

Thanks for contributing to Ref Fresh! This guide explains the project shape, the
boundaries to preserve, and the checks to run before sending changes.

## Project Overview

Ref Fresh is a zsh plugin for idle prompt redraws in Git repositories. It
watches the repository associated with the current shell prompt and asks zsh to
redraw when the worktree or Git metadata changes.

The plugin not render prompt content or compute Git prompt state. Instead, it
gives existing prompts a chance to re-run their own Git logic when something
changes outside the active shell, such as another terminal editing files or
switching branches.

The main implementation lives in `zsh-ref-fresh.zsh`. The `zsh-ref-fresh.plugin.zsh`
file is only a plugin-manager entrypoint that sources the main file.

## Project Boundaries

Ref Fresh should:

- register and remove zsh hooks cleanly
- detect whether the current directory is inside a Git worktree
- start one watcher for the active repository per shell
- watch the worktree root plus external Git metadata directories when needed
- stop the active watcher when the shell leaves a repository
- request a prompt redraw after repository change events
- fail quietly when `fswatch` or Git repository information is unavailable

Ref Fresh should not:

- render prompt text
- calculate dirty state
- choose colors or symbols
- format branch names
- cache prompt state
- require a specific prompt framework
- assume Grayt or any other theme is installed

The redraw is the interface. Compatible prompts recalculate their own Git state
when `PROMPT` or `RPROMPT` is re-expanded, often through `prompt_subst` and a
function call like `$(my_git_prompt)`.

## Public API

Public functions use the `ref_fresh_*` prefix:

```zsh
ref_fresh_start
ref_fresh_stop
ref_fresh_restart
ref_fresh_check_pwd
```

Private helpers use the `__ref_fresh_*` prefix. Keep private helpers internal
unless there is a clear user-facing reason to expose them.

Configuration currently uses environment variables:

```zsh
REF_FRESH_AUTO_START=1 # Controls source-time automatic startup.
REF_FRESH_LATENCY=0.5
REF_FRESH_BACKEND=fswatch
REF_FRESH_DEBUG=0
```

Most configuration is read dynamically when `ref_fresh_check_pwd` runs, but
`REF_FRESH_AUTO_START` is only read when the plugin is sourced.
`REF_FRESH_ENABLE` is supported as a deprecated fallback when
`REF_FRESH_AUTO_START` is unset. `REF_FRESH_LATENCY` is read when a watcher
starts, so changing it for an active watcher requires `ref_fresh_restart` or
moving to a different repository.

## Watcher Lifecycle

1. `ref_fresh_start` registers `ref_fresh_check_pwd` as a `precmd` hook and
   registers cleanup for `zshexit`.
2. `ref_fresh_check_pwd` runs before each prompt render.
3. If the backend is unsupported or `fswatch` is missing, the active watcher is
   stopped.
4. If the shell is not in a Git worktree, the active watcher is stopped.
5. If the shell is still in the already-watched worktree, nothing changes.
6. If the shell enters a different worktree, the old watcher is stopped and a
   new one starts.
7. `fswatch` writes batched events into a FIFO.
8. zsh watches the FIFO with `zle -F`.
9. `__ref_fresh_on_event` drains pending events and calls `zle .reset-prompt`.
10. `zshexit` cleanup stops the watcher and closes the FIFO descriptor.

The watcher observes the Git worktree root. It also observes `--git-dir` and
`--git-common-dir` when those directories live outside the worktree. This covers
normal repositories, linked worktrees, and repositories whose `.git` metadata
points elsewhere.

Noisy Git internals such as object writes, reflogs, lock files, fsmonitor-daemon
state, and `COMMIT_EDITMSG` are excluded before events reach zsh.

## Development Setup

Clone the repository and work from the checkout root:

```zsh
git clone https://github.com/evanthegrayt/zsh-ref-fresh
cd zsh-ref-fresh
```

The only runtime dependencies are zsh, Git, and `fswatch`. The automated smoke
test uses a fake `fswatch`, so it can run even when the real tool is not
installed.

For manual testing with real filesystem events, install `fswatch` through your
platform package manager, then source `zsh-ref-fresh.zsh` from an interactive zsh
session.

## Coding Guidelines

Keep changes small and centered on the watcher lifecycle. This plugin sits
inside interactive shells, so quiet failure and careful cleanup matter more than
clever output.

Use zsh-native patterns already present in the codebase:

- `emulate -L zsh` inside functions
- arrays for path and filter lists
- `GIT_OPTIONAL_LOCKS=0` for Git commands used by the plugin
- `add-zsh-hook` for hook registration
- `zle -F` for FIFO event handling
- private globals only for watcher state

Avoid adding dependencies unless they solve a real portability or correctness
problem. Any new dependency should be documented in the README.

Do not make unrelated style rewrites in the same change as behavior changes.
Shell code is easy to disturb accidentally, and small diffs are much easier to
review.

## Documentation Guidelines

Keep the README user-facing. It should explain what Ref Fresh does, how to
install it, how to configure it, and how prompt authors should consume redraws.

Keep maintainer and contributor notes in this file. Design constraints that
affect future development belong here.

Shell files use shdoc-style comments. File headers should include `@file`,
`@brief`, and `@description`. Function comments should describe arguments,
environment variables, outputs, changed globals, and exit codes where relevant.

Private functions should include `@internal` so generated API docs can focus on
the public surface.

## Tests

Run syntax checks first:

```zsh
zsh -n zsh-ref-fresh.zsh
zsh -n zsh-ref-fresh.plugin.zsh
zsh -n test/smoke.zsh
```

Run the smoke test:

```zsh
zsh test/smoke.zsh
```

The smoke test covers:

- disabled autostart
- missing `fswatch`
- fake `fswatch` startup and cleanup
- active repository root tracking
- same-repository watcher reuse
- stopping after leaving a repository
- replacing the watcher after switching repositories

When behavior changes touch watcher startup, shutdown, path selection, or hook
registration, update `test/smoke.zsh` in the same change.

## Manual Testing

Manual testing with the real `fswatch` backend is useful before releases:

1. Open two terminals in the same Git repository.
2. Source Ref Fresh in terminal A and leave it idle at the prompt.
3. Edit or stage files in terminal B.
4. Confirm terminal A redraws without pressing Enter.
5. Switch branches in terminal B.
6. Confirm terminal A redraws and the prompt reflects the new branch state.

Also test leaving the repository and entering another repository to make sure
the old watcher stops and a new watcher starts.

## Compatibility Notes

Prompts that calculate Git state during prompt expansion should work naturally.
Prompts that only calculate Git state in `precmd` and store it in a variable may
redraw stale cached values after `zle .reset-prompt`.

If a change is intended to support cached prompts, keep the feature generic. For
example, a user-defined callback is preferable to prompt-specific integration
code.

## Pull Request Checklist

Before opening a pull request, make sure:

- syntax checks pass
- the smoke test passes
- README changes are included for user-facing behavior
- shdoc comments are updated for changed functions
- new public API uses the `ref_fresh_*` prefix
- private helpers use the `__ref_fresh_*` prefix
- prompt rendering remains outside this plugin
