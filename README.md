# Ref Fresh

[![Shell: zsh](https://img.shields.io/static/v1?label=shell&message=zsh&color=4EAA25&style=flat&logo=shell&logoColor=white)](https://www.zsh.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/evanthegrayt/zsh-ref-fresh/actions/workflows/ci.yml/badge.svg)](https://github.com/evanthegrayt/zsh-ref-fresh/actions/workflows/ci.yml)

Ref Fresh keeps zsh prompts fresh while your shell is idle in a Git repository.
When another terminal or program edits files, changes branches, rebases, or
updates refs, Ref Fresh asks zsh to redraw the current prompt so your existing
prompt logic can recalculate Git state.

It does not render a prompt, choose a branch format, calculate dirty state, or
cache Git status. It only watches the current repository and calls `zle
.reset-prompt` after repository filesystem changes. If you're interested in a
full prompt, you can check out [my personal
prompt](https://github.com/evanthegrayt/grayt-zsh-theme). Just be aware you'll
still need this plugin for live updates to work.

## Requirements

- [Zsh](https://www.zsh.org/)
- [Git](https://git-scm.com/)
- [fswatch](https://github.com/emcrisostomo/fswatch)

Ref Fresh uses one `fswatch` process per current repository per shell. It watches
the worktree root, plus Git metadata directories when they live outside the
worktree, so branch switches and dirty-state changes use the same watcher.

If `fswatch` is not installed, Ref Fresh quietly does nothing.

## Install

### Manual

```zsh
source /path/to/zsh-ref-fresh/zsh-ref-fresh.zsh
```

### Oh My Zsh

Clone this repository into your custom plugins directory:

```zsh
git clone https://github.com/evanthegrayt/zsh-ref-fresh \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-ref-fresh
```

Then enable it:

```zsh
plugins=(... zsh-ref-fresh)
```

### zinit

```zsh
zinit light evanthegrayt/zsh-ref-fresh
```

### zplug

```zsh
zplug "evanthegrayt/zsh-ref-fresh"
```

### Other
...or use your other favorite manager's instructions.

## Setup

Ref Fresh starts automatically by default as soon as it is sourced. You do not
need to set `REF_FRESH_AUTO_START=1` for normal use.

Set `REF_FRESH_AUTO_START=0` before sourcing the plugin when you want the
functions available but do not want watchers to start until you run
`ref_fresh_start` yourself.

Set optional configuration variables in your zsh startup file before Ref Fresh
loads when you can. If you install Ref Fresh with a plugin manager, the plugin
manager usually sources the plugin for you; do not also source
`zsh-ref-fresh.zsh` manually.

For a manual install, set any optional variables and then source the plugin:

```zsh
# Optional: change the default 0.5 second fswatch latency.
REF_FRESH_LATENCY=2

source /path/to/zsh-ref-fresh/zsh-ref-fresh.zsh
```

For a plugin manager, put any optional variables before the manager loads Ref
Fresh:

```zsh
# Optional: change the default 0.5 second fswatch latency.
REF_FRESH_LATENCY=2

# Your plugin manager loads evanthegrayt/zsh-ref-fresh here.
```

Most configuration is read dynamically. `REF_FRESH_AUTO_START` is the exception:
it only controls whether Ref Fresh starts automatically when sourced, and its
default is `1` (enabled).

`REF_FRESH_LATENCY` is read when a watcher starts. If you change latency while a
watcher is already running, call `ref_fresh_restart` or wait until you enter a
different repository.

Configuration uses environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `REF_FRESH_AUTO_START` | `1` | Start Ref Fresh automatically when sourced. Set to `0` to skip automatic start-up.|
| `REF_FRESH_LATENCY` | `0.5` | Seconds passed to `fswatch --latency`. |
| `REF_FRESH_BACKEND` | `fswatch` | Watch backend. Only `fswatch` is supported today. |
| `REF_FRESH_DEBUG` | `0` | Print debug messages to stderr when truthy. |


If you disable automatic start-up, You can turn it on later in the current shell with:

```zsh
ref_fresh_start
```

## Commands

You can stop, start, and restart the current shell's hooks and watcher
directly:

```zsh
ref_fresh_stop
ref_fresh_start
ref_fresh_restart
```

The manual commands do not change `REF_FRESH_AUTO_START`. If
`REF_FRESH_AUTO_START=0`, `ref_fresh_start` and `ref_fresh_restart` still start
Ref Fresh in the current shell.

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

### Example

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

For a full prompt example, see [my personal
theme](https://github.com/evanthegrayt/grayt-zsh-theme/blob/master/grayt.zsh-theme).

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development notes, project boundaries,
and test commands.

## Inspiration

Ref Fresh was inspired by [Cobalt
Spark's](https://github.com/azhuchkov/cobalt-spark) Live Git updates. See
[LICENSE](LICENSE) for more details.

## Support this project
I love knowing when people find my work useful. Any kind of support is very much
appreciated!

- ⭐️ Like the project? Star [the repository](https://github.com/evanthegrayt/zsh-ref-fresh)!
- ❤️ Love the project? Follow me [on GitHub](https://github.com/evanthegrayt)!
- 💸 *Really* love it? Consider [buying me a tea](https://paypal.me/evanrgray)!
