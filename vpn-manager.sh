#!/bin/bash

set -u

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
CONFIG_FILE="$REPO_DIR/vpn.conf"
STATE_DIR="$HOME/Library/Application Support/OpenConnectMenuBar"
LOG_DIR="$STATE_DIR/logs"
CURRENT_FILE="$STATE_DIR/current-profile"

# Defaults; vpn.conf may override them.
OPENVPN=/opt/homebrew/sbin/openvpn
F5_APP="/Applications/F5 VPN.app"

IDS=() ENGINES=() TITLES=() LABELS=() TARGETS=()

# Called from vpn.conf: vpn ID ENGINE TITLE LABEL TARGET
vpn() {
  if [ "$#" -ne 5 ]; then
    echo "vpn.conf: 'vpn' needs 5 arguments, got $#: $*" >&2
    return 1
  fi
  IDS+=("$1") ENGINES+=("$2") TITLES+=("$3") LABELS+=("$4") TARGETS+=("$5")
}

# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"
F5_EXEC="$F5_APP/Contents/MacOS/F5 VPN"

mkdir -p "$STATE_DIR" "$LOG_DIR"

profile_ids() {
  [ "${#IDS[@]}" -gt 0 ] && printf '%s\n' "${IDS[@]}"
}

profile_index() {
  local i=0
  while [ "$i" -lt "${#IDS[@]}" ]; do
    if [ "${IDS[$i]}" = "$1" ]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

profile_label() {
  local i
  i=$(profile_index "$1") || return 1
  printf '%s\n' "${LABELS[$i]}"
}

profile_engine() {
  local i
  i=$(profile_index "$1") || return 1
  printf '%s\n' "${ENGINES[$i]}"
}

# openvpn: the .ovpn path (relative paths are relative to the repo); f5: the portal URL.
profile_target() {
  local i target
  i=$(profile_index "$1") || return 1
  target="${TARGETS[$i]}"
  case "$(profile_engine "$1"):$target" in
    openvpn:/*|f5:*) ;;
    openvpn:*) target="$REPO_DIR/$target" ;;
  esac
  printf '%s\n' "$target"
}

profile_log() {
  printf '%s/%s.log\n' "$LOG_DIR" "$1"
}

profile_pidfile() {
  printf '%s/%s.pid\n' "$STATE_DIR" "$1"
}

pid_is_alive() {
  local pid="$1"
  [ -n "$pid" ] && ps -p "$pid" -o pid= >/dev/null 2>&1
}

pid_matches_engine() {
  local pid="$1" engine="$2" command
  pid_is_alive "$pid" || return 1
  command=$(ps -p "$pid" -o command= 2>/dev/null || true)
  case "$engine" in
    openvpn) [[ "$command" == *openvpn* ]] ;;
    f5) [[ "$command" == *"$F5_EXEC" ]] ;;
    *) return 1 ;;
  esac
}

f5_client_pid() {
  pgrep -f "$F5_EXEC" | head -n 1
}

f5_client_running() {
  [ -n "$(f5_client_pid)" ]
}

tunnel_has_ipv4() {
  local dev
  for dev in $(/sbin/ifconfig -l 2>/dev/null | tr ' ' '\n' | grep '^utun'); do
    if /sbin/ifconfig "$dev" 2>/dev/null | grep -qE 'inet [0-9]'; then
      return 0
    fi
  done
  return 1
}

f5_tunnel_ready() {
  f5_client_running && tunnel_has_ipv4
}

tunnel_ready() {
  case "$(profile_engine "$1")" in
    f5) f5_tunnel_ready ;;
    openvpn) tunnel_has_ipv4 ;;
    *) return 1 ;;
  esac
}

active_profile() {
  local profile engine pid pidfile candidate
  if [ -r "$CURRENT_FILE" ]; then
    profile=$(cat "$CURRENT_FILE")
    if engine=$(profile_engine "$profile"); then
      pidfile=$(profile_pidfile "$profile")
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if pid_matches_engine "$pid" "$engine" && tunnel_ready "$profile"; then
        printf '%s\n' "$profile"
        return 0
      fi
      pid_is_alive "$pid" || rm -f "$pidfile"
    fi
    rm -f "$CURRENT_FILE"
  fi

  for candidate in $(profile_ids); do
    engine=$(profile_engine "$candidate")
    if [ "$engine" = f5 ]; then
      # shortcut: an F5 tunnel started outside the menu is adopted by the first f5 profile,
      # since the F5 client doesn't say which portal it is connected to.
      if f5_tunnel_ready; then
        printf '%s\n' "$candidate" >"$CURRENT_FILE"
        printf '%s\n' "$candidate"
        return 0
      fi
      continue
    fi
    pidfile=$(profile_pidfile "$candidate")
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if pid_matches_engine "$pid" "$engine" && tunnel_ready "$candidate"; then
      printf '%s\n' "$candidate" >"$CURRENT_FILE"
      printf '%s\n' "$candidate"
      return 0
    fi
    pid_is_alive "$pid" || rm -f "$pidfile"
  done
}

wait_for_pidfile() {
  local pidfile="$1" n=0
  while [ "$n" -lt 120 ]; do
    if [ -s "$pidfile" ]; then
      cat "$pidfile"
      return 0
    fi
    sleep 0.25
    n=$((n + 1))
  done
  return 1
}

wait_for_exit() {
  local pid="$1" n=0
  while pid_is_alive "$pid" && [ "$n" -lt 80 ]; do
    sleep 0.25
    n=$((n + 1))
  done
  ! pid_is_alive "$pid"
}

disconnect_current() {
  local profile stored_profile engine pidfile pid log candidate
  stored_profile=$(cat "$CURRENT_FILE" 2>/dev/null || true)
  profile=$(active_profile)
  [ -n "$profile" ] || profile="$stored_profile"
  if ! profile_label "$profile" >/dev/null 2>&1; then
    for candidate in $(profile_ids); do
      engine=$(profile_engine "$candidate")
      pidfile=$(profile_pidfile "$candidate")
      pid=$(cat "$pidfile" 2>/dev/null || true)
      if pid_matches_engine "$pid" "$engine"; then
        profile="$candidate"
        break
      fi
    done
  fi
  profile_label "$profile" >/dev/null 2>&1 || return 0
  [ -n "$profile" ] || return 0
  engine=$(profile_engine "$profile")
  pidfile=$(profile_pidfile "$profile")
  pid=$(cat "$pidfile" 2>/dev/null || true)
  log=$(profile_log "$profile")

  case "$engine" in
    openvpn)
      sudo -n /usr/bin/killall -TERM openvpn >>"$log" 2>&1 || true
      ;;
    f5)
      osascript -e "tell application \"$(basename "$F5_APP" .app)\" to quit" >>"$log" 2>&1 || true
      ;;
  esac

  if [ -n "$pid" ]; then
    wait_for_exit "$pid" || true
  fi
  rm -f "$CURRENT_FILE" "$pidfile"
}

wait_for_openvpn() {
  local profile="$1" log="$2" pidfile="$3" n=0
  while [ "$n" -lt 120 ]; do
    if grep -q 'Data Channel:' "$log" 2>/dev/null && tunnel_has_ipv4; then
      printf '%s\n' "$profile" >"$CURRENT_FILE"
      return 0
    fi
    if grep -Eq 'Options error|AUTH_FAILED|Exiting due to fatal error|Cannot open TUN/TAP' "$log" 2>/dev/null; then
      return 1
    fi
    if [ -s "$pidfile" ] && ! pid_is_alive "$(cat "$pidfile")"; then
      return 1
    fi
    sleep 0.5
    n=$((n + 1))
  done
  return 1
}

start_openvpn() {
  local profile="$1" config log pidfile
  config=$(profile_target "$profile")
  log=$(profile_log "$profile")
  pidfile=$(profile_pidfile "$profile")
  : >"$log"
  rm -f "$pidfile"
  sudo -n "$OPENVPN" --config "$config" --writepid "$pidfile" --log-append "$log" >>"$log" 2>&1 &
  if ! wait_for_pidfile "$pidfile" >/dev/null; then
    echo "OpenVPN did not create its pid file" >>"$log"
    return 1
  fi
  wait_for_openvpn "$profile" "$log" "$pidfile"
}

launch_f5() {
  local profile="$1" pid
  if [ ! -x "$F5_EXEC" ]; then
    echo "F5 VPN client not found: $F5_APP" >&2
    return 1
  fi
  /usr/bin/open -a "$F5_APP" >/dev/null 2>&1
  sleep 1
  pid=$(f5_client_pid || true)
  [ -n "$pid" ] && printf '%s\n' "$pid" >"$(profile_pidfile "$profile")"
  /usr/bin/open "$(profile_target "$profile")" >/dev/null 2>&1
}

connect_profile() {
  local profile="$1" engine
  engine=$(profile_engine "$profile") || {
    echo "Unknown VPN profile: $profile (see $CONFIG_FILE)" >&2
    return 2
  }

  case "$engine" in
    openvpn) disconnect_current; start_openvpn "$profile" ;;
    f5) disconnect_current; launch_f5 "$profile" ;;
    *) echo "Unknown engine '$engine' for profile $profile" >&2; return 2 ;;
  esac
}

# Prints "id<TAB>title<TAB>label" per configured VPN, for the menu.
list_profiles() {
  local i=0
  while [ "$i" -lt "${#IDS[@]}" ]; do
    printf '%s\t%s\t%s\n' "${IDS[$i]}" "${TITLES[$i]}" "${LABELS[$i]}"
    i=$((i + 1))
  done
}

case "${1:-status}" in
  status)
    if [ -n "$(active_profile)" ]; then
      printf '%s\n' connected
    else
      printf '%s\n' disconnected
    fi
    ;;
  profile)
    active_profile
    ;;
  list)
    list_profiles
    ;;
  connect)
    [ "$#" -ge 2 ] || { echo 'usage: vpn-manager.sh connect PROFILE' >&2; exit 2; }
    connect_profile "$2"
    ;;
  disconnect)
    disconnect_current
    ;;
  *)
    echo 'usage: vpn-manager.sh {status|profile|list|connect PROFILE|disconnect}' >&2
    exit 2
    ;;
esac
