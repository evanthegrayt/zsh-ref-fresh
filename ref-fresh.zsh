##
# @file ref-fresh.zsh
# @description Idle prompt redraws for Git repositories.
#
# Ref Fresh watches the current Git repository while zsh is sitting idle at a
# prompt. Filesystem events are batched by fswatch, delivered through a FIFO, and
# handled by zle -F. On change, Ref Fresh drains the pending batch and asks zsh
# to redraw the prompt with `zle .reset-prompt`.
#
# The plugin does not render prompt text, cache Git status, or decide branch and
# dirty-state formatting. Prompts remain responsible for recalculating their own
# state when zsh redraws.
#
# @env REF_FRESH_ENABLE Enables redraws when set to `1`, `true`, `yes`, or `on`.
# @env REF_FRESH_LATENCY Seconds passed to `fswatch --latency`; defaults to `0.5`.
# @env REF_FRESH_BACKEND Watch backend; only `fswatch` is supported.
# @env REF_FRESH_DEBUG Prints debug messages when truthy.

[[ -o interactive ]] || return 0 2> /dev/null || exit 0

autoload -Uz add-zsh-hook

if (( ! ${+__ref_fresh_events_fd} )); then
  typeset -gi __ref_fresh_events_fd=-1
  typeset -gi __ref_fresh_pid=-1
  typeset -g  __ref_fresh_root=
fi

function __ref_fresh_truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

function __ref_fresh_debug() {
  __ref_fresh_truthy "${REF_FRESH_DEBUG:-0}" || return 0
  print -ru2 -- "ref-fresh: $*"
}

function __ref_fresh_git() {
  GIT_OPTIONAL_LOCKS=0 command git "$@"
}

function __ref_fresh_enabled() {
  __ref_fresh_truthy "${REF_FRESH_ENABLE:-1}"
}

function __ref_fresh_latency() {
  emulate -L zsh
  setopt localoptions extendedglob

  local latency="${REF_FRESH_LATENCY:-0.5}"

  if [[ "$latency" != <->(|.<->) && "$latency" != .<-> ]]; then
    latency=0.5
  fi

  print -r -- "$latency"
}

function __ref_fresh_quote_ere() {
  local value="$1"

  value=${value//\\/\\\\}
  value=${value//\[/\\[}
  value=${value//\]/\\]}
  value=${value//./\\.}
  value=${value//\^/\\^}
  value=${value//\$/\\$}
  value=${value//\*/\\*}
  value=${value//+/\\+}
  value=${value//\?/\\?}
  value=${value//\(/\\(}
  value=${value//\)/\\)}
  value=${value//\{/\\{}
  value=${value//\}/\\}}
  value=${value//|/\\|}

  REPLY="$value"
}

function __ref_fresh_shutdown() {
  emulate -L zsh

  if (( __ref_fresh_events_fd >= 0 )); then
    zle -F "$__ref_fresh_events_fd" 2> /dev/null
    exec {__ref_fresh_events_fd}<&-
    __ref_fresh_events_fd=-1
  fi

  if (( __ref_fresh_pid > 0 )); then
    kill "$__ref_fresh_pid" 2> /dev/null
    wait "$__ref_fresh_pid" 2> /dev/null
    __ref_fresh_pid=-1
  fi

  __ref_fresh_root=
}

function __ref_fresh_on_event() {
  emulate -L zsh

  local fd="$1"
  local error="${2-}"
  local REPLY

  if [[ -n "$error" ]] || ! IFS= read -r -u "$fd"; then
    __ref_fresh_shutdown
    return 0
  fi

  while IFS= read -r -t 0 -u "$fd"; do
    :
  done

  zle .reset-prompt 2> /dev/null
}

function __ref_fresh_cleanup_fifo() {
  command rm -f -- "$1" 2> /dev/null
  command rmdir -- "$2" 2> /dev/null
}

function __ref_fresh_start_watcher() {
  emulate -L zsh
  setopt localoptions nobgnice

  local root="$1"
  local git_dir="$2"
  local common_dir="$3"
  shift 3

  local -a paths=("$@")
  local -a filters
  local dir tmpdir fifo_dir events_fifo events_fd latency

  for dir in "$git_dir" ${${common_dir:#$git_dir}:+"$common_dir"}; do
    __ref_fresh_quote_ere "$dir"
    filters+=(
      -e "^${REPLY}/objects(/.*)?$"
      -e "^${REPLY}/logs(/.*)?$"
      -e "^${REPLY}/fsmonitor--daemon(/.*)?$"
      -e "^${REPLY}/fsmonitor--daemon\\.ipc$"
      -e "^${REPLY}/.*\\.lock$"
      -e "^${REPLY}/COMMIT_EDITMSG$"
    )
  done

  tmpdir="${TMPDIR:-/tmp}"
  fifo_dir=$(command mktemp -d "${tmpdir%/}/ref-fresh.XXXXXX") || return 1
  events_fifo="$fifo_dir/events"

  command mkfifo "$events_fifo" || {
    __ref_fresh_cleanup_fifo "$events_fifo" "$fifo_dir"
    return 1
  }

  __ref_fresh_quote_ere "${fifo_dir:A}"
  filters+=(-e "^${REPLY}(/.*)?$")

  latency=$(__ref_fresh_latency)

  command fswatch --recursive --one-per-batch \
    --latency "$latency" \
    --monitor-property darwin.eventStream.noDefer=true \
    --extended --allow-overflow \
    "${filters[@]}" -- "${paths[@]}" > "$events_fifo" 2> /dev/null &!

  __ref_fresh_pid=$!

  exec {events_fd}< "$events_fifo" || {
    kill "$__ref_fresh_pid" 2> /dev/null
    wait "$__ref_fresh_pid" 2> /dev/null
    __ref_fresh_pid=-1
    __ref_fresh_cleanup_fifo "$events_fifo" "$fifo_dir"
    return 1
  }

  __ref_fresh_cleanup_fifo "$events_fifo" "$fifo_dir"

  __ref_fresh_root="$root"
  __ref_fresh_events_fd="$events_fd"

  if ! zle -F "$events_fd" __ref_fresh_on_event; then
    __ref_fresh_shutdown
    return 1
  fi

  __ref_fresh_debug "watching $root"
}

function ref_fresh_check_pwd() {
  emulate -L zsh

  if ! __ref_fresh_enabled; then
    __ref_fresh_shutdown
    return 0
  fi

  if [[ "${REF_FRESH_BACKEND:-fswatch}" != fswatch ]]; then
    __ref_fresh_debug "unsupported backend: ${REF_FRESH_BACKEND:-}"
    __ref_fresh_shutdown
    return 0
  fi

  if ! whence -p fswatch > /dev/null 2>&1; then
    __ref_fresh_debug "fswatch not found"
    __ref_fresh_shutdown
    return 0
  fi

  local -a git_dirs paths

  git_dirs=("${(@f)$(
    __ref_fresh_git rev-parse \
      --show-toplevel \
      --git-dir \
      --git-common-dir \
      2> /dev/null
  )}") || git_dirs=()

  if (( ${#git_dirs} != 3 )); then
    __ref_fresh_shutdown
    return 0
  fi

  local root="${git_dirs[1]:A}"
  local git_dir="${git_dirs[2]:A}"
  local common_dir="${git_dirs[3]:A}"

  [[ "$root" == "$__ref_fresh_root" ]] && return 0

  __ref_fresh_shutdown

  paths=("$root")

  [[ "$git_dir" != "$root" && "$git_dir" != "$root"/* ]] &&
    paths+=("$git_dir")

  [[ "$common_dir" != "$root" && "$common_dir" != "$root"/* && "$common_dir" != "$git_dir" ]] &&
    paths+=("$common_dir")

  __ref_fresh_start_watcher "$root" "$git_dir" "$common_dir" "${paths[@]}" || return 0
}

function ref_fresh_start() {
  emulate -L zsh

  add-zsh-hook -d precmd ref_fresh_check_pwd 2> /dev/null
  add-zsh-hook -d zshexit __ref_fresh_shutdown 2> /dev/null

  add-zsh-hook precmd ref_fresh_check_pwd
  add-zsh-hook zshexit __ref_fresh_shutdown

  ref_fresh_check_pwd
}

function ref_fresh_stop() {
  emulate -L zsh

  add-zsh-hook -d precmd ref_fresh_check_pwd 2> /dev/null
  add-zsh-hook -d zshexit __ref_fresh_shutdown 2> /dev/null

  __ref_fresh_shutdown
}

function ref_fresh_restart() {
  emulate -L zsh

  ref_fresh_stop
  ref_fresh_start
}

ref_fresh_start
