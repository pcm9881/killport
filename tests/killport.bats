#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../killport.sh"
}

# ── Version & help ───────────────────────────────────────────────────────────

@test "--version prints version" {
  run killport --version
  [ "$status" -eq 0 ]
  [[ "$output" == killport\ * ]]
}

@test "-v prints version" {
  run killport -v
  [ "$status" -eq 0 ]
  [[ "$output" == killport\ * ]]
}

@test "--help prints usage" {
  run killport --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage" {
  run killport -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── Argument validation ──────────────────────────────────────────────────────

@test "no arguments returns exit code 2" {
  run killport
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "invalid port (non-numeric) returns exit code 2" {
  run killport abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a valid port"* ]]
}

@test "port 0 returns exit code 2" {
  run killport 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"out of range"* ]]
}

@test "port 99999 returns exit code 2" {
  run killport 99999
  [ "$status" -eq 2 ]
  [[ "$output" == *"out of range"* ]]
}

@test "unknown option returns exit code 2" {
  run killport -z
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "invalid timeout returns exit code 2" {
  run killport --timeout=0 3000
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "invalid signal returns exit code 2" {
  run killport --signal=INVALID 3000
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown signal"* ]]
}

# ── No process on port ───────────────────────────────────────────────────────

@test "unused port returns exit code 1" {
  run killport 19999
  [ "$status" -eq 1 ]
  [[ "$output" == *"No process found"* ]]
}

@test "quiet mode suppresses output on unused port" {
  run killport --quiet 19999
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── Dry run ──────────────────────────────────────────────────────────────────

@test "dry-run shows process info without killing" {
  # Start a background process on a known port
  python3 -m http.server 18765 &>/dev/null &
  local bg_pid=$!
  sleep 1

  run killport --dry-run 18765
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]

  # Verify process is still alive
  kill -0 "$bg_pid" 2>/dev/null
  kill "$bg_pid" 2>/dev/null
  wait "$bg_pid" 2>/dev/null || true
}

# ── Signal helpers ───────────────────────────────────────────────────────────

@test "_killport_valid_signal accepts TERM" {
  run _killport_valid_signal TERM
  [ "$status" -eq 0 ]
}

@test "_killport_valid_signal accepts 15" {
  run _killport_valid_signal 15
  [ "$status" -eq 0 ]
}

@test "_killport_valid_signal accepts SIGTERM" {
  run _killport_valid_signal SIGTERM
  [ "$status" -eq 0 ]
}

@test "_killport_valid_signal rejects 0" {
  run _killport_valid_signal 0
  [ "$status" -ne 0 ]
}

@test "_killport_valid_signal rejects 99" {
  run _killport_valid_signal 99
  [ "$status" -ne 0 ]
}

@test "_killport_normalize_signal strips SIG prefix" {
  run _killport_normalize_signal SIGTERM
  [ "$output" = "TERM" ]
}

@test "_killport_normalize_signal uppercases" {
  run _killport_normalize_signal hup
  [ "$output" = "HUP" ]
}

# ── Exit priority ────────────────────────────────────────────────────────────

@test "_killport_worse_exit picks higher severity" {
  run _killport_worse_exit 0 1
  [ "$output" = "1" ]

  run _killport_worse_exit 1 126
  [ "$output" = "126" ]

  run _killport_worse_exit 126 2
  [ "$output" = "126" ]

  run _killport_worse_exit 130 1
  [ "$output" = "1" ]
}

# ── Combined short options ───────────────────────────────────────────────────

@test "combined -yq works" {
  run killport -yq 19999
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── -- ends options ──────────────────────────────────────────────────────────

@test "-- treats subsequent args as ports" {
  run killport --quiet -- 19999
  [ "$status" -eq 1 ]
}

# ── Actual kill ─────────────────────────────────────────────────────────────

@test "killport -y kills a process on a port" {
  python3 -m http.server 18766 &>/dev/null &
  local bg_pid=$!
  sleep 1

  run killport -y 18766
  [ "$status" -eq 0 ]

  # Verify process is dead
  ! kill -0 "$bg_pid" 2>/dev/null
  wait "$bg_pid" 2>/dev/null || true
}

@test "quiet mode with force kills successfully" {
  python3 -m http.server 18767 &>/dev/null &
  local bg_pid=$!
  sleep 1

  run killport -yq 18767
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  ! kill -0 "$bg_pid" 2>/dev/null
  wait "$bg_pid" 2>/dev/null || true
}

@test "quiet mode without force still kills (implies force)" {
  python3 -m http.server 18768 &>/dev/null &
  local bg_pid=$!
  sleep 1

  run killport -q 18768
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  ! kill -0 "$bg_pid" 2>/dev/null
  wait "$bg_pid" 2>/dev/null || true
}

# ── Argument edge cases ─────────────────────────────────────────────────────

@test "--timeout without value returns exit code 2" {
  run killport --timeout --signal=TERM 3000
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "--signal without value returns exit code 2" {
  run killport --signal --timeout=3 3000
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}
