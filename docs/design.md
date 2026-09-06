# Ref Fresh Design

Ref Fresh detects the current Git worktree, runs one watcher for that
repository, and asks zsh to redraw the prompt when repository files change.
Prompt rendering remains outside the plugin.

## Lifecycle

1. `ref_fresh_start` registers `ref_fresh_check_pwd` as a `precmd` hook and
   registers cleanup for `zshexit`.
2. `ref_fresh_check_pwd` runs before each prompt render.
3. If `REF_FRESH_ENABLE` is disabled, the active watcher is stopped.
4. If the shell is not in a Git worktree, the active watcher is stopped.
5. If the shell is still in the already-watched worktree, nothing changes.
6. If the shell enters a different worktree, the old watcher is stopped and a
   new one starts.
7. `fswatch` writes batched events into a FIFO.
8. zsh watches the FIFO with `zle -F`.
9. `__ref_fresh_on_event` drains pending events and calls `zle .reset-prompt`.

## Watched Paths

The watcher always observes the Git worktree root. It also observes `--git-dir`
and `--git-common-dir` when those directories live outside the worktree. This
covers normal repositories, linked worktrees, and repositories whose `.git`
metadata points elsewhere.

The watcher excludes noisy Git internals such as object writes, reflogs, lock
files, fsmonitor-daemon state, and `COMMIT_EDITMSG`.

## Boundaries

Ref Fresh never renders prompt content, calculates Git status, selects prompt
colors, or caches branch names. Any prompt that recalculates Git state during a
redraw can consume it.

## Attribution

Portions of the repository watcher logic are adapted from Cobalt Spark's Live
Git updates.
