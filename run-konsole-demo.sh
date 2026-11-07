#!/usr/bin/env bash
# Run demo steps from a YAML file: bash ./run-konsole-demo.sh demo.yaml

function usage()
{
    require-tools cat || return $?
    cat <<'HELP'
Usage: run-konsole-demo [--] FILE
       run-konsole-demo [-h|--help]

Open a new Konsole or Yakuake tab and run the demo steps from a YAML file:
    run-konsole-demo demo.yaml

YAML example (demo.yaml):
    - "Preparing the demo"
    - command: "echo hello"
      sleep: 0.5

Each step is a single-line string (a comment), or an object with exactly
one comment or command containing a single line, plus an optional
non-negative sleep duration in seconds.

After typing each step, the runner waits until the shell in the new tab
is idle (the command has finished), then sleeps for the step's sleep.
Comments without sleep use the default delay; commands without sleep
don't sleep at all. KONSOLE_DEMO_DEFAULT_SLEEP sets the default delay
(10 seconds).

Requirements:
    dotool for typing; yq v4 for YAML; qdbus-qt6 and ps for the new tab.
    Typing sends input to the focused window; keep the new tab focused.

Options:
    -h, --help               Show this help screen.
HELP
}

function die()
{
    printf '%s\n' "$*" >&2
    exit 1
}


function require-tools()
{
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'run-konsole-demo: required tool not found: %s\n' "$tool" >&2
            return 1
        fi
    done
}


function detect-terminal()
{
    require-tools ps || return $?
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
    require-tools qdbus-qt6 || return $?
    local before after path
    # addSession returns a Yakuake id, not the /Sessions/N object; find the new object instead.
    before=$(qdbus-qt6 org.kde.yakuake) || return $?
    qdbus-qt6 org.kde.yakuake /yakuake/sessions org.kde.yakuake.addSession >/dev/null || return $?
    after=$(qdbus-qt6 org.kde.yakuake) || return $?

    demo_service=org.kde.yakuake
    demo_session=
    while IFS= read -r path; do
        if [[ $path =~ ^/Sessions/[0-9]+$ && $'\n'$before$'\n' != *$'\n'"$path"$'\n'* ]]; then
            if [[ -n $demo_session ]]; then
                printf 'new-yakuake-tab: more than one new Yakuake session appeared\n' >&2
                return 1
            fi
            demo_session=$path
        fi
    done <<<"$after"

    if [[ -z $demo_session ]]; then
        printf 'new-yakuake-tab: cannot find the new Yakuake session\n' >&2
        return 1
    fi
}


function new-konsole-tab()
{
    if [[ -z ${KONSOLE_DBUS_SERVICE:-} || -z ${KONSOLE_DBUS_WINDOW:-} ]]; then
        printf 'new-konsole-tab: Konsole D-Bus environment is unavailable\n' >&2
        return 1
    fi

    require-tools qdbus-qt6 || return $?
    local id
    id=$(qdbus-qt6 "$KONSOLE_DBUS_SERVICE" "$KONSOLE_DBUS_WINDOW" org.kde.konsole.Window.newSession) \
        || return $?
    demo_service=$KONSOLE_DBUS_SERVICE
    demo_session=/Sessions/$id
}


function new-terminal-tab()
{
    local terminal
    terminal=$(detect-terminal) || return $?

    case $terminal in
        konsole) new-konsole-tab ;;
        yakuake) new-yakuake-tab ;;
        *) die "Unsupported terminal: $terminal" ;;
    esac || return $?

    demo_shell_pid=$(qdbus-qt6 "$demo_service" "$demo_session" org.kde.konsole.Session.processId)
}


function wait-for-shell()
{
    local fg_pid
    # Let the typed Enter reach the shell before checking its foreground process.
    sleep 0.2
    while :; do
        fg_pid=$(qdbus-qt6 "$demo_service" "$demo_session" org.kde.konsole.Session.foregroundProcessId) \
            || return $?
        (( fg_pid == demo_shell_pid )) && return 0
        sleep 0.5
    done
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

    local sleep_time_after=${3-}
    if (( $# == 2 )) && [[ $1 == comment ]]; then
        sleep_time_after=${KONSOLE_DEMO_DEFAULT_SLEEP:-10}
    fi
    if [[ -n $sleep_time_after && ! $sleep_time_after =~ ^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
        printf 'step: seconds must be a non-negative number\n' >&2
        return 2
    fi

    case $1 in
        comment) type-comment "$2" || return $? ;;
        command) type-command "$2" || return $? ;;
        *) printf 'step: unknown kind: %s\n' "$1" >&2; return 2 ;;
    esac
    wait-for-shell || return $?
    [[ -z $sleep_time_after ]] || sleep "$sleep_time_after"
}


function steps-from-yaml()
{
    if (( $# != 1 )); then
        printf 'Usage: steps-from-yaml FILE\n' >&2
        return 2
    fi
    require-tools yq dotool qdbus-qt6 ps || return $?
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
        | ((select(tag == "!!str") | {"comment": .}) // .)
        | (
            select(tag == "!!map")
          // error("each step must be an object or string")
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
    new-terminal-tab || return $?
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
    exit $?
fi

show_help=false
while getopts ':h-:' option; do
    if [[ $option == - && $OPTARG == help ]]; then
        option=h
    fi
    case $option in
        h) show_help=true ;;
        *)
            if [[ $option == - ]]; then
                OPTARG=-$OPTARG
            fi
            printf 'Unknown option: -%s\n' "$OPTARG" >&2
            usage >&2
            exit 2
            ;;
    esac
done
shift "$((OPTIND - 1))"

if $show_help && (( $# == 0 )); then
    usage
    exit $?
fi
if $show_help || (( $# != 1 )); then
    printf 'Expected exactly one YAML file.\n' >&2
    usage >&2
    exit 2
fi
steps-from-yaml "$1"
