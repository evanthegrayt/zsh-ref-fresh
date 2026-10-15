#!/usr/bin/env zsh
##
# @file smoke.zsh
# @brief Smoke tests for Ref Fresh.
# @description
#     Runs a small interactive zsh test harness that validates disabled
#     autostart, legacy disabled autostart, default autostart, missing fswatch
#     behavior, fake fswatch watcher startup, same-repository reuse, leaving a
#     repository, switching repositories, explicit cleanup, EOF, and signals.

if [[ ! -o interactive ]]; then
  exec zsh -fi "$0" "$@"
fi

emulate -L zsh
setopt err_return no_unset pipe_fail
zmodload zsh/zpty
zmodload zsh/zselect

typeset -r plugin_dir="${0:A:h:h}"
typeset -r plugin_file="$plugin_dir/zsh-ref-fresh.zsh"
typeset -r temp_dir="$(command mktemp -d "${TMPDIR:-/tmp}/zsh-ref-fresh-smoke.XXXXXX")"
typeset -r fake_bin="$temp_dir/bin"
typeset -r fake_log="$temp_dir/fswatch.log"
typeset -gi session_shell_pid=-1 session_watcher_pid=-1

##
# @description Stop the active watcher and remove temporary test files.
# @exitcode 0 Always succeeds.
function cleanup() {
  (( ${+functions[ref_fresh_stop]} )) && ref_fresh_stop
  zpty -d ref-fresh-test 2> /dev/null || true
  if (( session_shell_pid > 0 )); then
    kill -KILL "$session_shell_pid" 2> /dev/null || true
  fi
  if (( session_watcher_pid > 0 )); then
    kill -KILL "$session_watcher_pid" 2> /dev/null || true
  fi
  local ready_file watcher_pid
  for ready_file in "$temp_dir"/*.ready(N); do
    IFS= read -r watcher_pid < "$ready_file" || continue
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
# @description Assert that a file's first line matches an expected value.
# @arg $1 string Expected value.
# @arg $2 string File to read.
# @arg $3 string Assertion label.
# @exitcode 0 The file matches.
# @exitcode 1 The file could not be read or did not match.
function assert_file_eq() {
  local got
  IFS= read -r got < "$2" || fail "$3: could not read $2"
  assert_eq "$1" "$got" "$3"
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
# @description Wait for the prompt and the line editor's readiness acknowledgement.
# @exitcode 0 The prompt was received and the line editor is ready.
# @exitcode 1 The shell exited or did not reach its prompt.
function wait_for_session_prompt() {
  local output= chunk
  local -i attempt

  for attempt in {1..500}; do
    if zpty -r -t ref-fresh-test chunk; then
      output+="$chunk"
    fi
    [[ "$output" == *'REF_FRESH_TEST_PROMPT> '* && -s "$REF_FRESH_TEST_STATE" ]] && return 0
    zselect -t 1 || true
  done
  fail "test shell did not reach its prompt: $output"
}

##
# @description Start an interactive shell with a ready watcher under a PTY.
# @arg $1 integer Install a user HUP trap when set to 1; defaults to 0.
# @set session_shell_pid integer Shell PID.
# @set session_watcher_pid integer Watcher PID.
# @exitcode 0 The shell and watcher are ready.
# @exitcode 1 Startup failed.
function start_test_session() {
  export REF_FRESH_TEST_HUP_TRAP="${1:-0}"
  command rm -f -- "$REF_FRESH_TEST_STATE" "$REF_FRESH_TEST_READY" \
    "$REF_FRESH_TEST_EXIT" "$REF_FRESH_TEST_TRAP_LOG"
  zpty -b ref-fresh-test exec zsh -fi || fail "could not start test shell"
  zpty -w ref-fresh-test 'unsetopt ignoreeof; bindkey -e; cd -- "$REF_FRESH_TEST_REPO"'
  zpty -w ref-fresh-test 'if (( REF_FRESH_TEST_HUP_TRAP )); then trap '\''print -r -- user-hup > "$REF_FRESH_TEST_TRAP_LOG"'\'' HUP; fi'
  zpty -w ref-fresh-test 'REF_FRESH_AUTO_START=1; source "$REF_FRESH_TEST_PLUGIN"'
  zpty -w ref-fresh-test 'test_exit() { print -r -- "$__ref_fresh_pid:$__ref_fresh_events_fd:$__ref_fresh_root" > "$REF_FRESH_TEST_EXIT"; }; add-zsh-hook zshexit test_exit'
  zpty -w ref-fresh-test 'test_line_init() { print -r -- "$$ $__ref_fresh_pid" > "$REF_FRESH_TEST_STATE"; }; zle -N zle-line-init test_line_init'
  # Split the marker so echoed input cannot be mistaken for the actual prompt.
  zpty -w ref-fresh-test ': > "$REF_FRESH_TEST_STATE"; PROMPT="REF_FRESH_TEST_""PROMPT> "; RPROMPT='
  wait_for_session_prompt
  IFS=' ' read -r session_shell_pid session_watcher_pid < "$REF_FRESH_TEST_STATE" || fail "could not read session PIDs"
  (( session_shell_pid > 0 && session_watcher_pid > 0 )) || fail "session PIDs not set"

  wait_for_watcher "$REF_FRESH_TEST_READY"
  assert_file_eq "$session_watcher_pid" "$REF_FRESH_TEST_READY" "ready watcher PID"
  kill -0 "$session_watcher_pid" 2> /dev/null || fail "session watcher not alive"
}

##
# @description Assert that the shell exited and its hook stopped the watcher.
# @exitcode 0 Shell, watcher, and tracked state were cleaned up.
# @exitcode 1 Cleanup was incomplete.
function assert_session_cleaned_up() {
  local -i attempt
  local output= chunk running=no exit_state=missing

  for attempt in {1..500}; do
    # Drain output as a terminal emulator would; PTY exit detection needs this.
    while zpty -r -t ref-fresh-test chunk; do
      output+="$chunk"
    done
    if ! kill -0 "$session_shell_pid" 2> /dev/null && ! kill -0 "$session_watcher_pid" 2> /dev/null; then
      assert_file_eq '-1:-1:' "$REF_FRESH_TEST_EXIT" "exit hook cleared watcher state"
      zpty -d ref-fresh-test
      command rm -- "$REF_FRESH_TEST_READY"
      session_shell_pid=-1
      session_watcher_pid=-1
      return 0
    fi
    zselect -t 1 || true
  done
  while zpty -r -t ref-fresh-test chunk; do
    output+="$chunk"
  done
  kill -0 "$session_shell_pid" 2> /dev/null && running=yes
  [[ -r "$REF_FRESH_TEST_EXIT" ]] && IFS= read -r exit_state < "$REF_FRESH_TEST_EXIT"
  fail "shell or watcher remained alive after exit (shell=$running exit_hook=$exit_state watcher=$session_watcher_pid): $output"
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

  for attempt in {1..500}; do
    [[ -s "$ready_file" ]] && return 0
    zselect -t 1 || true
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
# Ignoring HUP ensures that the shell's cleanup hook must stop it explicitly.
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
    print -r -- 'trap "" HUP'
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

unset REF_FRESH_TEST_IGNORE_TERM REF_FRESH_TEST_READY

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

ref_fresh_stop
export REF_FRESH_TEST_PLUGIN="$plugin_file"
export REF_FRESH_TEST_REPO="$repo_a"
export REF_FRESH_TEST_STATE="$temp_dir/session.pids"
export REF_FRESH_TEST_READY="$temp_dir/session.ready"
export REF_FRESH_TEST_EXIT="$temp_dir/session.exit"
export REF_FRESH_TEST_TRAP_LOG="$temp_dir/session.trap"

start_test_session
zpty -w -n ref-fresh-test $'\x04'
assert_session_cleaned_up
pass "Ctrl-D at an idle prompt stops the watcher"

start_test_session
zpty -w ref-fresh-test exit
assert_session_cleaned_up
pass "explicit shell exit stops the watcher"

start_test_session
kill -HUP "$session_shell_pid"
assert_session_cleaned_up
pass "SIGHUP stops the watcher through the exit hook"

start_test_session
zpty -d ref-fresh-test
for attempt in {1..500}; do
  if ! kill -0 "$session_shell_pid" 2> /dev/null && ! kill -0 "$session_watcher_pid" 2> /dev/null; then
    break
  fi
  zselect -t 1 || true
done
kill -0 "$session_shell_pid" 2> /dev/null && fail "shell survived PTY closure"
kill -0 "$session_watcher_pid" 2> /dev/null && fail "watcher survived PTY closure"
assert_file_eq '-1:-1:' "$REF_FRESH_TEST_EXIT" "PTY closure cleanup"
command rm -- "$REF_FRESH_TEST_READY"
session_shell_pid=-1
session_watcher_pid=-1
pass "closing the pseudo-terminal stops the watcher"

for signal in INT TERM QUIT; do
  start_test_session
  command rm -- "$REF_FRESH_TEST_STATE"
  kill -"$signal" "$session_shell_pid"
  if [[ "$signal" == INT ]]; then
    # SIGINT can discard input while ZLE restarts; wait before typing again.
    wait_for_session_prompt
    command rm -- "$REF_FRESH_TEST_STATE"
  fi
  zpty -w ref-fresh-test 'print -r -- "$$ $__ref_fresh_pid" > "$REF_FRESH_TEST_STATE"'
  wait_for_session_prompt
  zpty -t ref-fresh-test || fail "$signal terminated the interactive shell"
  kill -0 "$session_watcher_pid" 2> /dev/null || fail "$signal stopped the active watcher"
  assert_file_eq "$session_shell_pid $session_watcher_pid" "$REF_FRESH_TEST_STATE" "$signal retains watcher"
  [[ ! -e "$REF_FRESH_TEST_EXIT" ]] || fail "$signal unexpectedly ran exit cleanup"
  zpty -w ref-fresh-test exit
  assert_session_cleaned_up
  pass "SIG$signal preserves the session and watcher until shell exit"
done

start_test_session 1
command rm -- "$REF_FRESH_TEST_STATE"
kill -HUP "$session_shell_pid"
zpty -w ref-fresh-test 'print -r -- "$$ $__ref_fresh_pid" > "$REF_FRESH_TEST_STATE"'
wait_for_session_prompt
assert_file_eq user-hup "$REF_FRESH_TEST_TRAP_LOG" "user HUP trap preserved"
assert_file_eq "$session_shell_pid $session_watcher_pid" "$REF_FRESH_TEST_STATE" "user HUP trap retains watcher"
kill -0 "$session_watcher_pid" 2> /dev/null || fail "user HUP trap stopped the watcher"
[[ ! -e "$REF_FRESH_TEST_EXIT" ]] || fail "user HUP trap unexpectedly ran exit cleanup"
zpty -w ref-fresh-test exit
assert_session_cleaned_up
pass "an existing user HUP trap retains control of signal handling"

export REF_FRESH_TEST_IGNORE_TERM=1
start_test_session
zpty -w -n ref-fresh-test $'\x04'
assert_session_cleaned_up
pass "Ctrl-D terminates a watcher that ignores TERM"

start_test_session
kill -HUP "$session_shell_pid"
assert_session_cleaned_up
pass "SIGHUP terminates a watcher that ignores TERM"
unset REF_FRESH_TEST_IGNORE_TERM

start_test_session
kill -KILL "$session_shell_pid"
for attempt in {1..500}; do
  zpty -r -t ref-fresh-test chunk || true
  kill -0 "$session_shell_pid" 2> /dev/null || break
  zselect -t 1 || true
done
kill -0 "$session_shell_pid" 2> /dev/null && fail "SIGKILL did not terminate the test shell"
[[ ! -e "$REF_FRESH_TEST_EXIT" ]] || fail "SIGKILL unexpectedly ran exit cleanup"
kill -0 "$session_watcher_pid" 2> /dev/null || fail "SIGKILL test watcher not alive"
kill -TERM "$session_watcher_pid"
for attempt in {1..500}; do
  kill -0 "$session_watcher_pid" 2> /dev/null || break
  zselect -t 1 || true
done
kill -0 "$session_watcher_pid" 2> /dev/null && fail "SIGKILL test watcher teardown failed"
zpty -d ref-fresh-test
command rm -- "$REF_FRESH_TEST_READY"
session_shell_pid=-1
session_watcher_pid=-1
pass "SIGKILL bypasses shell cleanup (test removes the surviving watcher)"
