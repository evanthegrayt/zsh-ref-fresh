# Ref Fresh

Ref Fresh keeps zsh prompts fresh while your shell is idle in a Git repository.
When another terminal or program edits files, changes branches, rebases, or
updates refs, Ref Fresh asks zsh to redraw the current prompt so your existing
prompt logic can recalculate Git state.

It does not render a prompt, choose a branch format, calculate dirty state, or
cache Git status. It only watches the current repository and calls
`zle .reset-prompt` after repository filesystem changes.

Ref Fresh was inspired by [Cobalt
Spark's](https://github.com/azhuchkov/cobalt-spark) Live Git updates.

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

## Use In A Prompt

Ref Fresh does not include Git prompt rendering code, and it does not pass branch
or dirty-state information to your prompt. There is no hidden variable to read.

The flow is:

1. Your prompt renders Git information however it normally does.
2. Ref Fresh notices that files in the current repository changed.
3. Ref Fresh calls `zle .reset-prompt`.
4. zsh redraws the prompt.
5. Your prompt's own Git code runs again during that redraw.

That means your prompt should calculate Git information during prompt expansion,
or call a function from `PROMPT`/`RPROMPT` while `prompt_subst` is enabled.

For example:

```zsh
setopt prompt_subst

function my_git_prompt() {
  command git rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 0

  local ref dirty
  ref=$(command git symbolic-ref --short HEAD 2> /dev/null) \
    || ref=$(command git rev-parse --short HEAD 2> /dev/null) \
    || return 0

  if [[ -n "$(command git status --porcelain 2> /dev/null)" ]]; then
    dirty="*"
  fi

  print -r -- " [$ref$dirty]"
}

PROMPT='%~$(my_git_prompt) %# '
```

Ref Fresh will make that `$(my_git_prompt)` call happen again when another
terminal changes the repository. The plugin does not decide what `my_git_prompt`
returns.

For a full prompt example, see
[grayt.zsh-theme](https://github.com/evanthegrayt/grayt-zsh-theme/blob/master/grayt.zsh-theme).

If your prompt only calculates Git state in a `precmd` hook and stores it in a
variable, a prompt reset may redraw the old cached value. In that case, move the
Git calculation into a prompt-expansion function, or have your prompt expose a
function that recalculates the cache during redraw.

## Prompt Compatibility

Ref Fresh works with any zsh prompt that recalculates its Git state during a
prompt redraw. The most direct pattern is a function called while rendering
`PROMPT` or `RPROMPT`.

Because Ref Fresh only triggers redraws, your prompt remains responsible for
deciding what to show.
