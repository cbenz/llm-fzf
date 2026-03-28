#!/usr/bin/env bash

require_commands() {
    local missing=()
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
        return 1
    fi
}

format_error_message() {
    local error_text="$1"
    local single_line

    single_line="$(printf '%s' "$error_text" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    if [ -z "$single_line" ]; then
        printf 'Unknown error'
        return
    fi

    printf '%.180s' "$single_line"
}

notify_init() {
    NOTIFY_APP_NAME="$1"
    NOTIFY_IDFILE="$2"
}

notify_message() {
    local message="$1"
    local timeout="${2:-0}"
    local args=(--printid --app-name="$NOTIFY_APP_NAME" -t "$timeout")
    local notify_id

    if [ -f "$NOTIFY_IDFILE" ]; then
        args+=(--replace-id="$(cat "$NOTIFY_IDFILE")")
    fi

    notify_id="$(dunstify "${args[@]}" "$NOTIFY_APP_NAME" "$message")" || return 1
    printf '%s' "$notify_id" > "$NOTIFY_IDFILE"
}

close_notification() {
    if [ -f "$NOTIFY_IDFILE" ]; then
        dunstify --close="$(cat "$NOTIFY_IDFILE")" >/dev/null 2>&1 || true
        rm -f "$NOTIFY_IDFILE"
    fi
}

start_spinner() {
    local label="$1"

    stop_spinner

    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0

        while true; do
            notify_message "$label ${frames[$i]}" || true
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.15
        done
    ) &

    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "${SPINNER_PID:-}" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
}

detect_clipboard_tool() {
    if command -v xclip >/dev/null 2>&1; then
        CLIPBOARD_TOOL="xclip"
        return 0
    fi
    if command -v xsel >/dev/null 2>&1; then
        CLIPBOARD_TOOL="xsel"
        return 0
    fi
    return 1
}

fzf_menu() {
    if ! command -v xterm >/dev/null 2>&1; then
        echo "Error: xterm is not installed." >&2
        return 1
    fi

    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is not installed." >&2
        return 1
    fi

    local fzf_menu_font="${LLM_FZF_MENU_FONT:-monospace:size=10}"
    local input_file output_file
    input_file="$(mktemp)"
    output_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$input_file' '$output_file'" RETURN

    cat > "$input_file"

    xterm \
        -fa "$fzf_menu_font" \
        -title "fzf-menu" \
        -e bash -c 'fzf "${@:3}" < "$1" > "$2"' bash "$input_file" "$output_file" "$@"

    local exit_code=$?
    cat "$output_file"
    return $exit_code
}

clipboard_read_primary() {
    case "$CLIPBOARD_TOOL" in
        xclip) xclip -o -selection primary ;;
        xsel) xsel --output --primary ;;
    esac
}

clipboard_write_clipboard() {
    local value="$1"
    case "$CLIPBOARD_TOOL" in
        xclip) printf '%s' "$value" | xclip -in -selection clipboard ;;
        xsel) printf '%s' "$value" | xsel --input --clipboard ;;
    esac
}

clipboard_write_primary() {
    local value="$1"
    case "$CLIPBOARD_TOOL" in
        xclip) printf '%s' "$value" | xclip -in -selection primary ;;
        xsel) printf '%s' "$value" | xsel --input --primary ;;
    esac
}

clipboard_write_both() {
    local value="$1"
    clipboard_write_clipboard "$value"
    clipboard_write_primary "$value"
}

clipboard_paste_via_shift_insert() {
    local value="$1"
    local hold_delay="${LLM_SHIFT_INSERT_HOLD_DELAY_SEC:-0.04}"
    local key_status=0

    clipboard_write_both "$value"

    # Hold Shift briefly before and after Insert to avoid occasional plain Insert.
    xdotool keydown Shift || return 1
    sleep "$hold_delay"
    xdotool key Insert || key_status=$?
    sleep "$hold_delay"
    xdotool keyup Shift || true

    return "$key_status"
}
