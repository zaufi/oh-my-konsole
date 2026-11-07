#!/usr/bin/env bash
# Run demo steps from a YAML file: bash ./run-konsole-demo.sh demo.yaml

function usage()
{
    cat <<'HELP'
Usage: run-konsole-demo FILE
       run-konsole-demo [-h|--help]

Run the demo steps from a YAML file:
    run-konsole-demo demo.yaml

YAML example (demo.yaml):
    - comment: "Preparing the demo"
    - command: "echo hello"
      sleep: 0.5

Each step has exactly one comment or command containing a single line,
plus an optional non-negative sleep duration in seconds.
KONSOLE_DEMO_DEFAULT_SLEEP sets the default delay (10 seconds).

Requirements:
    dotool for typing; yq v4 for YAML.
    Typing sends input to the focused window; focus the intended terminal.

Options:
    -h, --help                       Show this help screen.
HELP
}

function die()
{
    printf '%s\n' "$*" >&2
    exit 1
}


function detect-terminal()
{
    local pid=$$ parent name

    while (( pid > 1 )); do
        read -r parent name < <(ps -p "$pid" -o ppid= -o comm= 2>/dev/null) || break
        case $name in
            konsole|yakuake)
                printf '%s\n' "$name"
                return 0
                ;;
        esac
        pid=$parent
    done

    printf 'undetected\n'
}


function new-yakuake-tab()
{
    qdbus-qt6 org.kde.yakuake /yakuake/sessions org.kde.yakuake.addSession
}


function new-konsole-tab()
{
    if [[ -z ${KONSOLE_DBUS_SERVICE:-} || -z ${KONSOLE_DBUS_WINDOW:-} ]]; then
        printf 'new-konsole-tab: Konsole D-Bus environment is unavailable\n' >&2
        return 1
    fi

    qdbus-qt6 "$KONSOLE_DBUS_SERVICE" "$KONSOLE_DBUS_WINDOW" org.kde.konsole.Window.newSession
}


function new-terminal-tab()
{
    local terminal
    terminal=$(detect-terminal)

    case $terminal in
        konsole) new-konsole-tab ;;
        yakuake) new-yakuake-tab ;;
        *) die "Unsupported terminal: $terminal" ;;
    esac
}


function type-raw-text()
{
    if (( $# != 1 )); then
        printf 'Usage: type-raw-text "text"\n' >&2
        return 2
    fi

    case $1 in
        *$'\n'*|*$'\r'*)
            printf 'type-raw-text: text must contain a single line\n' >&2
            return 2
            ;;
    esac
    printf 'type %s\n' "$1" | dotool
}


function type-command()
{
    type-raw-text "$@" || return $?
    printf 'key enter\n' | dotool
}


function type-comment()
{
    if (( $# != 1 )); then
        printf 'Usage: type-comment "text"\n' >&2
        return 2
    fi

    type-command " # $1"
}


function step()
{
    if (( $# < 2 || $# > 3 )); then
        printf 'Usage: step comment|command "text" [seconds]\n' >&2
        return 2
    fi

    local sleep_time_after=${3-${KONSOLE_DEMO_DEFAULT_SLEEP:-10}}
    if [[ ! $sleep_time_after =~ ^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
        printf 'step: seconds must be a non-negative number\n' >&2
        return 2
    fi

    case $1 in
        comment) type-comment "$2" || return $? ;;
        command) type-command "$2" || return $? ;;
        *) printf 'step: unknown kind: %s\n' "$1" >&2; return 2 ;;
    esac
    sleep "${sleep_time_after}"
}


function steps-from-yaml()
{
    if (( $# != 1 )); then
        printf 'Usage: steps-from-yaml FILE\n' >&2
        return 2
    fi
    if ! command -v yq >/dev/null 2>&1; then
        printf 'steps-from-yaml: yq v4 is required\n' >&2
        return 1
    fi
    if [[ ! -r $1 ]]; then
        printf 'steps-from-yaml: cannot read file: %s\n' "$1" >&2
        return 1
    fi

    local steps kind text delay
    # Capture and validate the whole file before typing any of its steps.
    steps=$(yq eval-all -p=yaml -N -r '
        [.]
        | (
            select(length == 1 and (.[0] | tag) == "!!seq")
          // error("expected one YAML document containing an array")
          )
        | .[0]
        | .[]
        | (
            select(tag == "!!map")
          // error("each step must be an object")
          )
        | (
            select(
                ((keys - ["comment", "command", "sleep"]) | length) == 0
              and (keys | length) == (keys | unique | length)
              and (has("comment") != has("command"))
              )
          // error("expected unique keys: exactly one comment or command, and optional sleep")
          )
        | (
            select(
                ((.comment // .command) | tag) == "!!str"
              and (((.comment // .command) | test("[\n\r\x00]")) | not)
              )
          // error("step text must be a string without newline, carriage return, or NUL")
          )
        | (
            select(
                (has("sleep") | not)
              or (
                    (
                        (.sleep | tag) == "!!int"
                      or (.sleep | tag) == "!!float"
                      )
                  and (.sleep | @json | test("^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$"))
                  )
              )
          // error("sleep must be a non-negative number")
          )
        | [
            (keys - ["sleep"] | .[0]),
            (.comment // .command),
            (
                (select(has("sleep")) | .sleep | @json)
              // "default"
              )
          ]
        | .[]
    ' <"$1") || return $?

    [[ -n $steps ]] || return 0
    while IFS= read -r kind && IFS= read -r text && IFS= read -r delay; do
        if [[ $delay == default ]]; then
            step "$kind" "$text" || return $?
        else
            step "$kind" "$text" "$delay" || return $?
        fi
    done <<<"$steps"
}


if (( $# == 0 )); then
    usage
    exit 0
fi
if (( $# != 1 )); then
    printf 'Expected exactly one YAML file.\n' >&2
    usage >&2
    exit 2
fi
case $1 in
    -h|--help)
        usage
        exit 0
        ;;
    -*)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac
steps-from-yaml "$1"
