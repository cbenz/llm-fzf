#!/bin/bash

STATE_DIR="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/dictate"
REC_FILE="$STATE_DIR/dictate.wav"
REC_PIDFILE="$STATE_DIR/arecord.pid"
WORKER_PIDFILE="$STATE_DIR/worker.pid"
NOTIFY_IDFILE="$STATE_DIR/notification.id"
POSTPROCESS_ENABLED="${DICTATE_POSTPROCESS:-0}"
POSTPROCESS_PROMPT="${DICTATE_PROCESS_PROMPT:-}"

mkdir -p "$STATE_DIR"

require_deps() {
    local deps=(arecord llm xclip xdotool dunstify)
    local missing=()
    local dep

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
        printf 'Install the missing commands and retry.\n' >&2
        exit 1
    fi
}

notify() {
    local message="$1"
    local timeout="${2:-0}"
    local args=(--printid --app-name="dictate" -t "$timeout")
    local notify_id

    if [ -f "$NOTIFY_IDFILE" ]; then
        args+=(--replace-id="$(cat "$NOTIFY_IDFILE")")
    fi

    notify_id="$(dunstify "${args[@]}" "$message")" || return
    printf '%s' "$notify_id" > "$NOTIFY_IDFILE"
}

close_notification() {
    if [ -f "$NOTIFY_IDFILE" ]; then
        dunstify --close="$(cat "$NOTIFY_IDFILE")" >/dev/null 2>&1 || true
        rm -f "$NOTIFY_IDFILE"
    fi
}

is_running_pidfile() {
    local pidfile="$1"

    if [ ! -f "$pidfile" ]; then
        return 1
    fi

    kill -0 "$(cat "$pidfile")" 2>/dev/null
}

recording_active() {
    if is_running_pidfile "$REC_PIDFILE"; then
        return 0
    fi

    rm -f "$REC_PIDFILE"
    return 1
}

kill_from_pidfile() {
    local pidfile="$1"
    local signal="$2"

    if is_running_pidfile "$pidfile"; then
        kill "$signal" "$(cat "$pidfile")" 2>/dev/null
    fi

    rm -f "$pidfile"
}

start() {
    rm -f "$REC_FILE"

    notify "🎤 Recording..."

    arecord -f S16_LE -r 16000 -c 1 -t wav "$REC_FILE" &
    echo $! > "$REC_PIDFILE"

    (
        # Wait for recording to finish
        while is_running_pidfile "$REC_PIDFILE"; do
            sleep 0.1
        done

        raw_transcript="$(llm groq-whisper - < "$REC_FILE")"
        if [ -n "$raw_transcript" ]; then
            if [ "$POSTPROCESS_ENABLED" = "1" ] && [ -n "$POSTPROCESS_PROMPT" ]; then
                # Post-process the raw transcript with punctuation, typo fixes and style tweaks.
                if transcript="$(printf '%s' "$raw_transcript" | llm --system "$POSTPROCESS_PROMPT")"; then
                    :
                else
                    transcript="$raw_transcript"
                fi
            else
                transcript="$raw_transcript"
            fi

            # Copy to both CLIPBOARD (modern apps) and PRIMARY (Unix terminals)
            printf '%s' "$transcript" | xclip -selection clipboard -in
            printf '%s' "$transcript" | xclip -selection primary -in
            xdotool key --clearmodifiers Shift+Insert
        fi
        close_notification
        rm -f "$WORKER_PIDFILE"
    ) &
    echo $! > "$WORKER_PIDFILE"
}

stop() {
    if recording_active; then
        kill_from_pidfile "$REC_PIDFILE" -INT
        notify "⏳ Transcribing..."
    fi
}

cancel() {
    if ! recording_active; then
        echo "No recording in progress"
        return 0
    fi

    kill_from_pidfile "$REC_PIDFILE" -INT
    kill_from_pidfile "$WORKER_PIDFILE" -TERM
    notify "🛑 Recording cancelled" 1000
}

toggle() {
    if recording_active; then
        stop
    else
        start
    fi
}

status() {
    if recording_active || is_running_pidfile "$WORKER_PIDFILE"; then
        echo "working"
    else
        echo "idle"
    fi
}

usage() {
    cat <<'EOF'
Usage: dictate.sh [--prompt "<prompt>"|--postprocess|--no-postprocess] <command>

Commands:
  start   Start recording
  stop    Stop recording and transcribe
  cancel  Cancel recording
  toggle  Start if idle, stop if recording
  status  Show status (idle or working)

Options:
    --prompt <prompt>  Run transcript post-processing with the provided prompt
    --postprocess     Enable transcript post-processing (prompt from env)
    --no-postprocess  Disable transcript post-processing (default)

Environment:
    DICTATE_POSTPROCESS=0|1  Default post-processing mode (default: 0)
    DICTATE_PROCESS_PROMPT    Prompt used when post-processing is enabled
EOF
}

require_deps

command=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        start|stop|cancel|toggle|status)
            if [ -n "$command" ]; then
                echo "Only one command can be provided" >&2
                exit 1
            fi
            command="$1"
            ;;
        --postprocess)
            POSTPROCESS_ENABLED="1"
            ;;
        --prompt)
            if [ "$#" -lt 2 ]; then
                echo "Missing prompt for --prompt" >&2
                usage
                exit 1
            fi
            POSTPROCESS_ENABLED="1"
            POSTPROCESS_PROMPT="$2"
            shift
            ;;
        --no-postprocess)
            POSTPROCESS_ENABLED="0"
            ;;
        -h|--help|help)
            command="help"
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

case "$command" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    cancel)
        cancel
        ;;
    toggle)
        toggle
        ;;
    status)
        status
        ;;
    ""|help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
