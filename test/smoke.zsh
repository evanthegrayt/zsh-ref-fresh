#!/usr/bin/env zsh
##
# @file smoke.zsh
# @brief Smoke tests for Ref Fresh.
# @description
#     Runs a small interactive zsh test harness that validates disabled mode,
#     missing fswatch behavior, fake fswatch watcher startup, same-repository
#     reuse, leaving a repository, switching repositories, and explicit cleanup.

if [[ ! -o interactive ]]; then
  exec zsh -fi "$0" "$@"
fi

emulate -L zsh
setopt err_return no_unset pipe_fail

typeset -r plugin_dir="${0:A:h:h}"
typeset -r plugin_file="$plugin_dir/zsh-ref-fresh.zsh"
typeset -r temp_dir="$(command mktemp -d "${TMPDIR:-/tmp}/zsh-ref-fresh-smoke.XXXXXX")"
typeset -r fake_bin="$temp_dir/bin"
typeset -r fake_log="$temp_dir/fswatch.log"

##
# @description Stop the active watcher and remove temporary test files.
# @exitcode 0 Always succeeds.
function cleanup() {
  (( ${+functions[ref_fresh_stop]} )) && ref_fresh_stop
  command rm -rf -- "$temp_dir"
}

trap cleanup EXIT

##
# @description Print a passing test line.
#
# @arg $1 string Test description.
# @stdout TAP-style passing test line.
# @exitcode 0 Always succeeds.
function pass() {
  print -r -- "ok - $1"
}

##
# @description Print a failing test line and return a failure status.
#
# @arg $1 string Failure description.
# @stderr TAP-style failing test line.
# @exitcode 1 Always fails.
function fail() {
  print -ru2 -- "not ok - $1"
  return 1
}

##
# @description Assert that two strings are equal.
#
# @arg $1 string Expected value.
# @arg $2 string Actual value.
# @arg $3 string Assertion label.
# @stderr Failure details when values differ.
# @exitcode 0 Values are equal.
# @exitcode 1 Values differ.
function assert_eq() {
  local want="$1"
  local got="$2"
  local label="$3"

  [[ "$want" == "$got" ]] || fail "$label: expected '$want', got '$got'"
}

##
# @description Assert that a command succeeds.
#
# @arg $1 string Assertion label.
# @arg $@ string Command and arguments to run.
# @stderr Failure details when the command fails.
# @exitcode 0 Command succeeds.
# @exitcode 1 Command fails.
function assert_true() {
  local label="$1"
  shift

  "$@" || fail "$label"
}

##
# @description Assert that Ref Fresh has no active watcher.
#
# @arg $1 string Assertion label.
# @stderr Failure details when watcher state is still active.
# @exitcode 0 No watcher is active.
# @exitcode 1 Watcher state is active or inconsistent.
function assert_no_watcher() {
  local label="$1"

  assert_eq "-1" "$__ref_fresh_pid" "$label pid"
  assert_eq "-1" "$__ref_fresh_events_fd" "$label fd"
  assert_eq "" "$__ref_fresh_root" "$label root"
}

##
# @description Assert that Ref Fresh has an active watcher process.
#
# @arg $1 string Assertion label.
# @stderr Failure details when watcher state is inactive or inconsistent.
# @exitcode 0 A watcher is active.
# @exitcode 1 No watcher is active or watcher state is inconsistent.
function assert_watcher_alive() {
  local label="$1"

  (( __ref_fresh_pid > 0 )) || fail "$label pid not set"
  kill -0 "$__ref_fresh_pid" 2> /dev/null || fail "$label pid not alive"
  (( __ref_fresh_events_fd >= 0 )) || fail "$label fd not set"
}

##
# @description Create an empty Git repository for smoke testing.
#
# @arg $1 string Repository directory path.
# @exitcode 0 Repository was created.
# @exitcode non-zero Directory creation or `git init` failed.
function make_repo() {
  local dir="$1"

  command mkdir -p -- "$dir"
  builtin cd "$dir"
  command git init -q
}

##
# @description Install a fake fswatch executable earlier in PATH.
#
# The fake process records its invocation, traps termination, and sleeps until
# Ref Fresh stops the watcher.
#
# @set fake_bin string Directory containing the fake executable.
# @set fake_log string File where fake fswatch invocations are recorded.
# @exitcode 0 Fake executable was created.
# @exitcode non-zero Fake executable setup failed.
function install_fake_fswatch() {
  command mkdir -p -- "$fake_bin"
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- 'print -r -- "$PWD|$*" >> "$REF_FRESH_TEST_LOG"'
    print -r -- 'trap "exit 0" TERM INT'
    print -r -- 'while true; do sleep 60; done'
  } > "$fake_bin/fswatch"
  command chmod +x "$fake_bin/fswatch"
}

typeset -r original_path="$PATH"
typeset -r repo_a="$temp_dir/repo-a"
typeset -r repo_b="$temp_dir/repo-b"
typeset -r outside="$temp_dir/outside"

command mkdir -p -- "$outside"
make_repo "$repo_a"
make_repo "$repo_b"
install_fake_fswatch

export REF_FRESH_TEST_LOG="$fake_log"
export PATH="$fake_bin:$original_path"

export REF_FRESH_ENABLE=0
source "$plugin_file"
builtin cd "$repo_a"
ref_fresh_check_pwd
assert_no_watcher "disabled"
pass "disabled config starts no watcher"

##
# @description Override command lookup to simulate missing fswatch.
#
# @arg $@ string Arguments passed to `whence`.
# @stdout Delegated output from the builtin for commands other than fswatch.
# @stderr Delegated errors from the builtin for commands other than fswatch.
# @exitcode 1 The requested command is fswatch.
# @exitcode non-zero Delegated status from builtin `whence` for other commands.
function whence() {
  if [[ "${@: -1}" == fswatch ]]; then
    return 1
  fi

  builtin whence "$@"
}

export REF_FRESH_ENABLE=1
ref_fresh_restart
assert_no_watcher "missing fswatch"
pass "missing fswatch is a graceful no-op"

unfunction whence

ref_fresh_restart
assert_watcher_alive "repo a"
assert_eq "${repo_a:A}" "$__ref_fresh_root" "repo root stored"
typeset -i first_pid="$__ref_fresh_pid"
pass "fake fswatch watcher starts"

command mkdir -p -- "$repo_a/subdir"
builtin cd "$repo_a/subdir"
ref_fresh_check_pwd
assert_watcher_alive "same repo"
assert_eq "$first_pid" "$__ref_fresh_pid" "same repo reuses watcher"
pass "same repo reuses the active watcher"

builtin cd "$outside"
ref_fresh_check_pwd
assert_no_watcher "outside repo"
pass "leaving repo stops watcher"

builtin cd "$repo_a"
ref_fresh_check_pwd
assert_watcher_alive "repo a restart"
typeset -i old_pid="$__ref_fresh_pid"

builtin cd "$repo_b"
ref_fresh_check_pwd
assert_watcher_alive "repo b"
assert_eq "${repo_b:A}" "$__ref_fresh_root" "repo b root stored"
(( __ref_fresh_pid != old_pid )) || fail "switching repos should replace watcher"
kill -0 "$old_pid" 2> /dev/null && fail "old watcher still alive"
pass "switching repos replaces the watcher"

ref_fresh_stop
assert_no_watcher "explicit stop"
pass "explicit stop cleans up"
