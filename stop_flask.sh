#!/usr/bin/env bash
# Stop Flask servers (flask run, python app.py, gunicorn).
#
# By default only servers belonging to THIS project are stopped - this laptop
# runs Flask apps for several other projects, so a blind pkill would take them
# all down. Use -a to sweep every Flask server you own.
#
# Sends SIGTERM first, waits, then SIGKILL anything still alive.
#
# Usage:
#   ./stop_flask.sh              # stop this project's Flask servers
#   ./stop_flask.sh 5566 8000    # only stop whatever is listening on these ports
#   ./stop_flask.sh -a           # stop EVERY Flask/gunicorn process you own
#   ./stop_flask.sh -n           # dry run: list what would be killed
#   ./stop_flask.sh -f           # skip the grace period, SIGKILL straight away
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

GRACE_SECONDS="${GRACE_SECONDS:-5}"
DRY_RUN=0
FORCE=0
ALL=0

while getopts ":nfah" opt; do
  case "$opt" in
    n) DRY_RUN=1 ;;
    f) FORCE=1 ;;
    a) ALL=1 ;;
    h)
      sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      exit 2
      ;;
  esac
done
shift $((OPTIND - 1))

PORTS=("$@")
PIDS=()

add_pid() {
  local pid="$1"
  [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && return
  [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && return
  kill -0 "$pid" 2>/dev/null || return
  local existing
  for existing in "${PIDS[@]+"${PIDS[@]}"}"; do
    [[ "$existing" == "$pid" ]] && return
  done
  PIDS+=("$pid")
}

pids_on_port() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -t -i "TCP:${port}" -sTCP:LISTEN 2>/dev/null
  elif command -v fuser >/dev/null 2>&1; then
    fuser "${port}/tcp" 2>/dev/null | tr ' ' '\n'
  elif command -v ss >/dev/null 2>&1; then
    ss -lptnH "sport = :${port}" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2
  fi
}

if ((${#PORTS[@]} > 0)); then
  for port in "${PORTS[@]}"; do
    while read -r pid; do add_pid "$pid"; done < <(pids_on_port "$port")
  done
else
  # Match the ways Flask gets started, restricted to the current user.
  while read -r pid; do
    if ((ALL)); then
      add_pid "$pid"
    else
      # Scope to this project: either the process runs from here, or this
      # directory appears in its command line.
      cwd="$(readlink -f "/proc/$pid/cwd" 2>/dev/null)"
      cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
      if [[ "$cwd" == "$PROJECT_DIR" || "$cwd" == "$PROJECT_DIR"/* || "$cmdline" == *"$PROJECT_DIR"* ]]; then
        add_pid "$pid"
      fi
    fi
  done < <(pgrep -u "$(id -u)" -f 'flask +run|gunicorn|[Pp]ython[0-9.]* +.*app\.py|werkzeug' 2>/dev/null)
fi

if ((${#PIDS[@]} == 0)); then
  if ((${#PORTS[@]} > 0)); then
    echo "No listeners found on port(s): ${PORTS[*]}"
  elif ((ALL)); then
    echo "No Flask servers running."
  else
    echo "No Flask servers running for this project ($PROJECT_DIR)."
    echo "Use -a to stop every Flask server you own, or pass port numbers."
  fi
  exit 0
fi

echo "Found ${#PIDS[@]} process(es):"
for pid in "${PIDS[@]}"; do
  printf '  %-8s %s\n' "$pid" "$(ps -p "$pid" -o args= 2>/dev/null | cut -c1-100)"
done

if ((DRY_RUN)); then
  echo "Dry run - nothing killed."
  exit 0
fi

if ((FORCE)); then
  echo "Sending SIGKILL..."
  kill -9 "${PIDS[@]}" 2>/dev/null
else
  echo "Sending SIGTERM..."
  kill -15 "${PIDS[@]}" 2>/dev/null

  for ((i = 0; i < GRACE_SECONDS; i++)); do
    still_running=0
    for pid in "${PIDS[@]}"; do
      kill -0 "$pid" 2>/dev/null && still_running=1
    done
    ((still_running)) || break
    sleep 1
  done

  STUBBORN=()
  for pid in "${PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null && STUBBORN+=("$pid")
  done

  if ((${#STUBBORN[@]} > 0)); then
    echo "Still alive after ${GRACE_SECONDS}s, sending SIGKILL: ${STUBBORN[*]}"
    kill -9 "${STUBBORN[@]}" 2>/dev/null
    sleep 1
  fi
fi

FAILED=()
for pid in "${PIDS[@]}"; do
  kill -0 "$pid" 2>/dev/null && FAILED+=("$pid")
done

if ((${#FAILED[@]} > 0)); then
  echo "Could not stop: ${FAILED[*]} (try sudo)" >&2
  exit 1
fi

echo "All Flask servers stopped."
