# Ref Fresh

Ref Fresh keeps zsh prompts fresh while your shell is idle in a Git repository.
When another terminal or program edits files, changes branches, rebases, or
updates refs, Ref Fresh asks zsh to redraw the current prompt so your existing
prompt logic can recalculate Git state.

It does not render a prompt, choose a branch format, calculate dirty state, or
cache Git status. It only watches the current repository and calls
`zle .reset-prompt` after repository filesystem changes.

Ref Fresh was inspired by Cobalt Spark's Live Git updates.

## Requirements

- zsh
- Git
- [`fswatch`](https://github.com/emcrisostomo/fswatch)

Ref Fresh uses one `fswatch` process per current repository per shell. It watches
the worktree root, plus Git metadata directories when they live outside the
worktree, so branch switches and dirty-state changes use the same watcher.

If `fswatch` is not installed, Ref Fresh quietly does nothing.

## Install

### Manual

```zsh
REF_FRESH_ENABLE=1
REF_FRESH_LATENCY=0.5
source /path/to/ref-fresh/ref-fresh.zsh
```

### Oh My Zsh

Clone this repository into your custom plugins directory:

```zsh
git clone https://github.com/evanthegrayt/zsh-reffresh \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/ref-fresh
```

Then enable it:

```zsh
plugins=(... ref-fresh)
```

### zinit

```zsh
zinit light evanthegrayt/zsh-reffresh
```

### zplug

```zsh
zplug "evanthegrayt/zsh-reffresh"
```

### antidote

Add this to your bundle file:

```text
evanthegrayt/zsh-reffresh
```

Then rebuild your antidote bundle.

## Configure

```zsh
REF_FRESH_ENABLE=1
REF_FRESH_LATENCY=0.5
source /path/to/ref-fresh/ref-fresh.zsh
```

Configuration uses environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `REF_FRESH_ENABLE` | `1` | Enable prompt redraws. Truthy values are `1`, `true`, `yes`, and `on`. |
| `REF_FRESH_LATENCY` | `0.5` | Seconds passed to `fswatch --latency`. |
| `REF_FRESH_BACKEND` | `fswatch` | Watch backend. Only `fswatch` is supported today. |
| `REF_FRESH_DEBUG` | `0` | Print debug messages to stderr when truthy. |

Disable Ref Fresh with:

```zsh
REF_FRESH_ENABLE=0
```

You can also stop and restart it from an interactive shell:

```zsh
ref_fresh_stop
ref_fresh_start
ref_fresh_restart
```

`ref_fresh_check_pwd` is the public hook function. It checks the current
directory, starts a watcher when you enter a Git worktree, reuses the active
watcher while you move inside the same worktree, and stops the watcher when you
leave the repository.

## Prompt Compatibility

Ref Fresh works with any zsh prompt that recalculates its Git state during a
prompt redraw. That includes prompts that compute branch and dirty markers in
`precmd`, prompt expansion, or functions called while rendering `PROMPT` or
`RPROMPT`.

Because Ref Fresh only triggers redraws, your prompt remains responsible for
deciding what to show.
