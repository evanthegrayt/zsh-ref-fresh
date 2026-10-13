#!/usr/bin/env zsh
##
# @file smoke.zsh
# @brief Smoke tests for Ref Fresh.
# @description
#     Runs a small interactive zsh test harness that validates disabled
#     autostart, legacy disabled autostart, default autostart, missing fswatch
#     behavior, fake fswatch watcher startup, same-repository reuse, leaving a
#     repository, switching repositories, explicit cleanup, and shell EOF.

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
  local ready_file watcher_pid
  for ready_file in "$temp_dir"/*.ready(N); do
    IFS= read -r watcher_pid < "$ready_file"
    kill -KILL "$watcher_pid" 2> /dev/null || true
  done
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
# @description Print a failing test line and exit with a failure status.
#
# @arg $1 string Failure description.
# @stderr TAP-style failing test line.
# @exitcode 1 Always exits with failure.
function fail() {
  print -ru2 -- "not ok - $1"
  exit 1
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
# @description Assert that a watcher has exited, allowing signal delivery time.
# @arg $1 integer Watcher PID.
# @arg $2 string Assertion label.
# @exitcode 0 Watcher exited.
# @exitcode 1 Watcher remained alive.
function assert_watcher_stopped() {
  local watcher_pid="$1" label="$2"
  local -i attempt

  for attempt in {1..100}; do
    kill -0 "$watcher_pid" 2> /dev/null || return 0
    command sleep 0.01
  done
  fail "$label: watcher still alive"
}

##
# @description Wait for the fake watcher to install its signal handler.
# @arg $1 string Readiness file.
# @exitcode 0 Watcher is ready.
# @exitcode 1 Watcher did not become ready.
function wait_for_watcher() {
  local ready_file="$1"
  local -i attempt

  for attempt in {1..100}; do
    [[ -s "$ready_file" ]] && return 0
    command sleep 0.01
  done
  fail "watcher did not become ready"
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
# The fake process records its invocation and waits without spawning children.
# It can ignore TERM to exercise forced termination.
#
# @set fake_bin string Directory containing the fake executable.
# @set fake_log string File where fake fswatch invocations are recorded.
# @exitcode 0 Fake executable was created.
# @exitcode non-zero Fake executable setup failed.
function install_fake_fswatch() {
  command mkdir -p -- "$fake_bin"
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- 'zmodload zsh/zselect'
    print -r -- 'if [[ "${REF_FRESH_TEST_IGNORE_TERM:-0}" == 1 ]]; then'
    print -r -- '  trap "" TERM'
    print -r -- 'else'
    print -r -- '  trap "exit 0" TERM INT'
    print -r -- 'fi'
    print -r -- 'print -r -- "$PWD|$*" >> "$REF_FRESH_TEST_LOG"'
    print -r -- '[[ -n "${REF_FRESH_TEST_READY:-}" ]] && print -r -- "$$" > "$REF_FRESH_TEST_READY"'
    print -r -- 'while true; do zselect -t 6000; done'
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

export REF_FRESH_AUTO_START=0
unset REF_FRESH_ENABLE
source "$plugin_file"
assert_no_watcher "disabled autostart"
pass "disabled config skips automatic startup"

builtin cd "$repo_a"

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

ref_fresh_start
assert_no_watcher "missing fswatch"
pass "missing fswatch is a graceful no-op"

unfunction whence

ref_fresh_restart
assert_watcher_alive "repo a"
assert_eq "${repo_a:A}" "$__ref_fresh_root" "repo root stored"
typeset -i first_pid="$__ref_fresh_pid"
pass "manual start works with disabled autostart"

command mkdir -p -- "$repo_a/subdir"
builtin cd "$repo_a/subdir"
ref_fresh_check_pwd
assert_watcher_alive "same repo"
assert_eq "$first_pid" "$__ref_fresh_pid" "same repo reuses watcher"
pass "same repo reuses the active watcher"

builtin cd "$outside"
ref_fresh_check_pwd
assert_no_watcher "outside repo"
assert_watcher_stopped "$first_pid" "leaving repo"
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

typeset -i stopped_pid="$__ref_fresh_pid"
ref_fresh_stop
assert_no_watcher "explicit stop"
assert_watcher_stopped "$stopped_pid" "explicit stop"
pass "explicit stop cleans up"

builtin cd "$repo_a"
export REF_FRESH_TEST_IGNORE_TERM=1
export REF_FRESH_TEST_READY="$temp_dir/stubborn.ready"
ref_fresh_start
wait_for_watcher "$REF_FRESH_TEST_READY"
typeset -i stubborn_pid="$__ref_fresh_pid"
ref_fresh_stop
assert_no_watcher "stubborn stop"
assert_watcher_stopped "$stubborn_pid" "stubborn stop"
command rm -- "$REF_FRESH_TEST_READY"
pass "explicit stop terminates a watcher that ignores TERM"

export REF_FRESH_TEST_READY="$temp_dir/eof.ready"
export REF_FRESH_TEST_PLUGIN="$plugin_file"
export REF_FRESH_TEST_REPO="$repo_a"
export REF_FRESH_TEST_PID_FILE="$temp_dir/eof.pid"
REF_FRESH_AUTO_START=1 command zsh -fi > "$temp_dir/eof.stdout" 2> "$temp_dir/eof.stderr" <<'ZSH'
unsetopt ignoreeof
cd -- "$REF_FRESH_TEST_REPO"
source "$REF_FRESH_TEST_PLUGIN"
for attempt in {1..100}; do
  [[ -s "$REF_FRESH_TEST_READY" ]] && break
  command sleep 0.01
done
[[ -s "$REF_FRESH_TEST_READY" ]] || exit 1
print -r -- "$__ref_fresh_pid" > "$REF_FRESH_TEST_PID_FILE"
ZSH
typeset -i eof_pid="$(< "$REF_FRESH_TEST_PID_FILE")"
(( eof_pid > 0 )) || fail "EOF watcher pid not set"
assert_watcher_stopped "$eof_pid" "shell EOF"
command rm -- "$REF_FRESH_TEST_READY"
unset REF_FRESH_TEST_IGNORE_TERM REF_FRESH_TEST_READY
pass "shell EOF terminates a watcher that ignores TERM"

unset REF_FRESH_AUTO_START
export REF_FRESH_ENABLE=0
builtin cd "$repo_a"
source "$plugin_file"
assert_no_watcher "legacy disabled autostart"
pass "legacy disabled config skips automatic startup"

unset REF_FRESH_AUTO_START
unset REF_FRESH_ENABLE
builtin cd "$repo_a"
source "$plugin_file"
assert_watcher_alive "default autostart"
pass "default config starts automatically"
