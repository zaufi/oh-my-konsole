#!/usr/bin/env bats

setup()
{
    bats_require_minimum_version 1.5.0
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file

    script=$BATS_TEST_DIRNAME/../run-konsole-demo.sh
    export DEMO_TEST_LOG=$BATS_TEST_TMPDIR/actions
    export KONSOLE_DEMO_DEFAULT_SLEEP=0.25
    : >"$DEMO_TEST_LOG"
    mkdir "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/dotool" <<'EOF'
#!/usr/bin/env bash
case $1 in
    --list-keys) printf '%s\n' 'esc    k:1' 'l      k:38' 'q      k:16' 'pageup k:104' ;;
    --list-x-keys) printf '%s\n' 'Escape k:1' 'exclam shift+k:2' ;;
    *) cat >>"$DEMO_TEST_LOG" ;;
esac
EOF
    cat >"$BATS_TEST_TMPDIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$1" >>"$DEMO_TEST_LOG"
EOF
    cat >"$BATS_TEST_TMPDIR/bin/ps" <<'EOF'
#!/usr/bin/env bash
printf '1 %s\n' "${DEMO_TEST_TERMINAL:-konsole}"
EOF
    cat >"$BATS_TEST_TMPDIR/bin/qdbus-qt6" <<'EOF'
#!/usr/bin/env bash
if (( $# == 1 )); then
    # List the service objects; a Yakuake session appears after addSession.
    printf '/Sessions/1\n'
    if [[ -e $DEMO_TEST_LOG.added ]]; then
        printf '%s\n' ${DEMO_TEST_NEW_SESSIONS-/Sessions/3}
    fi
    exit 0
fi
printf 'dbus %s %s %s\n' "$1" "$2" "${3##*.}" >>"$DEMO_TEST_LOG"
case $3 in
    *.newSession) printf '3\n' ;;
    *.addSession) : >"$DEMO_TEST_LOG.added"; printf '0\n' ;;
    *.processId) printf '100\n' ;;
    *.foregroundProcessId)
        # $DEMO_TEST_LOG.busy holds how many polls still report a running command.
        busy=$(cat "$DEMO_TEST_LOG.busy" 2>/dev/null || printf 0)
        if (( busy > 0 )); then
            printf '%s\n' "$((busy - 1))" >"$DEMO_TEST_LOG.busy"
            printf '200\n'
        else
            printf '100\n'
        fi
        ;;
esac
exit "${DEMO_TEST_TAB_STATUS:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/"{dotool,sleep,ps,qdbus-qt6}
    export PATH=$BATS_TEST_TMPDIR/bin:$PATH
    export KONSOLE_DBUS_SERVICE=org.kde.konsole.test
    export KONSOLE_DBUS_WINDOW=/Windows/1

    cat >"$BATS_TEST_TMPDIR/demo steps.yaml" <<'EOF'
- comment: "Preparing the demo"
- command: "echo hello"
  sleep: 0.5
EOF

    konsole_tab=$'dbus org.kde.konsole.test /Windows/1 newSession\ndbus org.kde.konsole.test /Sessions/3 processId'
    idle=$'sleep 0.2\ndbus org.kde.konsole.test /Sessions/3 foregroundProcessId'
    demo_log="$konsole_tab"$'\ntype  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\n'"$idle"$'\nsleep 0.5'
}

run_without_tool()
{
    local missing=$1 tool tool_bin=$BATS_TEST_TMPDIR/without-$1
    shift
    mkdir "$tool_bin"
    for tool in bash cat dotool sleep ps qdbus-qt6; do
        if [[ $tool != "$missing" ]]; then
            ln -s "$(command -v "$tool")" "$tool_bin/$tool"
        fi
    done
    if [[ $missing != yq ]]; then
        printf '#!%s\nPATH=%q exec %q "$@"\n' \
            "$(command -v bash)" "$PATH" "$(command -v yq)" >"$tool_bin/yq"
        chmod +x "$tool_bin/yq"
    fi
    run --separate-stderr env PATH="$tool_bin" "$(command -v bash)" "$script" "$@"
}

@test "reports missing demo tools before typing any steps" {
    local tool
    for tool in dotool yq qdbus-qt6 ps; do
        run_without_tool "$tool" "$BATS_TEST_TMPDIR/demo steps.yaml"
        assert_file_empty "$DEMO_TEST_LOG"
        assert_failure 1
        assert_output ''
        assert_stderr --partial "required tool not found: $tool"
    done
}

@test "shows help without demo tools" {
    local tool
    for tool in yq dotool; do
        run_without_tool "$tool" --help
        assert_success
        assert_output --partial 'Usage: run-konsole-demo'
        assert_stderr ''
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "reports missing cat when showing help" {
    run_without_tool cat --help
    assert_failure 1
    assert_output ''
    assert_stderr --partial 'required tool not found: cat'
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "runs YAML from a path containing spaces with default and explicit delays" {
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_success
    assert_output ''
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$demo_log"
}

@test "runs string steps as comments alongside object steps" {
    cat >"$BATS_TEST_TMPDIR/demo steps.yaml" <<'EOF'
- Preparing the demo
- comment: "Existing comment"
  sleep: 0.5
- command: "echo hello"
- "Finished: ready"
EOF
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_success
    assert_output ''
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype  # Preparing the demo\nkey enter\nsleep 0.25\ntype  # Existing comment\nkey enter\nsleep 0.5\ntype echo hello\nkey enter\n'"$idle"$'\ntype  # Finished: ready\nkey enter\nsleep 0.25'
}

@test "accepts empty and quoted numeric string steps as comments" {
    printf '%s\n' '- ""' '- "42"' >"$BATS_TEST_TMPDIR/strings.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/strings.yaml"
    assert_success
    assert_output ''
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype  # \nkey enter\nsleep 0.25\ntype  # 42\nkey enter\nsleep 0.25'
}

@test "uses ten seconds for string steps when the default delay is unset" {
    unset KONSOLE_DEMO_DEFAULT_SLEEP
    printf '%s\n' '- Preparing the demo' >"$BATS_TEST_TMPDIR/strings.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/strings.yaml"
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype  # Preparing the demo\nkey enter\nsleep 10'
}

@test "rejects control characters in string steps before typing any steps" {
    local text
    for text in '"line\nbreak"' '"carriage\rreturn"' '"nul\0byte"'; do
        printf '%s\n' '- command: "echo valid"' "- $text" >"$BATS_TEST_TMPDIR/invalid.yaml"
        run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
        assert_failure 1
        assert_stderr --partial 'step text must be a string without newline, carriage return, or NUL'
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "rejects non-string scalar and nested array steps before typing any steps" {
    local value
    for value in 42 0.5 true false null '[]'; do
        printf '%s\n' '- command: "echo valid"' "- $value" >"$BATS_TEST_TMPDIR/invalid.yaml"
        run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
        assert_failure 1
        assert_stderr --partial 'each step must be an object or string'
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "waits for a running command and sleeps only when asked" {
    printf '%s\n' '- command: "make demo"' '- command: "echo done"' >"$BATS_TEST_TMPDIR/wait.yaml"
    printf '2\n' >"$DEMO_TEST_LOG.busy"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/wait.yaml"
    assert_success
    assert_stderr ''
    local poll=$'dbus org.kde.konsole.test /Sessions/3 foregroundProcessId'
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype make demo\nkey enter\nsleep 0.2\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\ntype echo done\nkey enter\n'"$idle"
}

@test "stops when the session cannot be polled" {
    printf '%s\n' '- command: "echo hello"' >"$BATS_TEST_TMPDIR/one.yaml"
    sed -i 's/^    \*\.foregroundProcessId)$/&\n        exit 5/' "$BATS_TEST_TMPDIR/bin/qdbus-qt6"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/one.yaml"
    assert_failure 5
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype echo hello\nkey enter\n'"$idle"
}

@test "opens a Yakuake tab and watches its new session" {
    export DEMO_TEST_TERMINAL=yakuake
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_success
    assert_stderr ''
    local poll=$'sleep 0.2\ndbus org.kde.yakuake /Sessions/3 foregroundProcessId'
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'dbus org.kde.yakuake /yakuake/sessions addSession\ndbus org.kde.yakuake /Sessions/3 processId\ntype  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\n'"$poll"$'\nsleep 0.5'
}

@test "stops before typing when the new Yakuake session is not unique" {
    local sessions
    for sessions in '' '/Sessions/3 /Sessions/4'; do
        : >"$DEMO_TEST_LOG"
        rm -f "$DEMO_TEST_LOG.added"
        DEMO_TEST_TERMINAL=yakuake DEMO_TEST_NEW_SESSIONS=$sessions run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml"
        assert_failure 1
        assert_stderr --partial 'new-yakuake-tab:'
        assert_equal "$(cat "$DEMO_TEST_LOG")" 'dbus org.kde.yakuake /yakuake/sessions addSession'
    done
}

@test "sends key steps without waiting and sleeps only when asked" {
    printf '%s\n' '- key: "ctrl+l"' '- key: "shift+pageup x:exclam  k:104 Esc"' '  sleep: 0.5' >"$BATS_TEST_TMPDIR/keys.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/keys.yaml"
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\nkey ctrl+l\nkey shift+pageup x:exclam  k:104 Esc\nsleep 0.5'
}

@test "drives an interactive command with wait false and key steps" {
    cat >"$BATS_TEST_TMPDIR/top.yaml" <<'EOF'
- command: "top"
  wait: false
  sleep: 3
- key: "q"
- key: "ctrl+l"
  wait: true
- comment: "done"
  wait: true
  sleep: 0
EOF
    printf '5\n' >"$DEMO_TEST_LOG.busy"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/top.yaml"
    assert_success
    assert_stderr ''
    local poll=$'dbus org.kde.konsole.test /Sessions/3 foregroundProcessId'
    # The busy counter is consumed only by the first explicit wait.
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$konsole_tab"$'\ntype top\nkey enter\nsleep 3\nkey q\nkey ctrl+l\nsleep 0.2\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\nsleep 0.5\n'"$poll"$'\ntype  # done\nkey enter\n'"$idle"$'\nsleep 0'
}

@test "rejects unknown keys before opening a tab" {
    local chord
    for chord in shift+pgup hyper+l +l x:nosuch x: k:abc ctrl+ '' ' ' 'l esc pgdn'; do
        printf '%s\n' '- command: "echo valid"' "- key: '$chord'" >"$BATS_TEST_TMPDIR/invalid.yaml"
        run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
        assert_failure 1
        assert_stderr --regexp 'unknown (key|modifier) in chord|needs at least one chord'
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "rejects invalid wait values and mixed step kinds before typing" {
    local step
    for step in '{command: x, wait: "no"}' '{key: q, wait: 1}' '{command: x, key: q}' '{comment: x, key: q}'; do
        printf '%s\n' "- $step" >"$BATS_TEST_TMPDIR/invalid.yaml"
        run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
        assert_failure 1
        assert_stderr --regexp 'wait must be true or false|exactly one comment, command or key'
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "stops before typing when opening a tab fails" {
    export DEMO_TEST_TAB_STATUS=7
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_failure 7
    assert_equal "$(cat "$DEMO_TEST_LOG")" 'dbus org.kde.konsole.test /Windows/1 newSession'
}

@test "rejects the removed -t option" {
    run --separate-stderr bash "$script" -t "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_failure 2
    assert_stderr --partial 'Unknown option: -t'
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "accepts a filename beginning with a dash after --" {
    cp "$BATS_TEST_TMPDIR/demo steps.yaml" "$BATS_TEST_TMPDIR/-t"
    cd "$BATS_TEST_TMPDIR" || return
    run --separate-stderr bash "$script" -- -t
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" "$demo_log"
}

@test "shows help without typing for both help options" {
    for option in -h --help; do
        run --separate-stderr bash "$script" "$option"
        assert_success
        assert_output --partial 'Usage:'
        assert_stderr ''
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "shows help without arguments" {
    run --separate-stderr bash "$script"
    assert_success
    assert_output --partial 'Usage:'
    assert_stderr ''
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "rejects unknown options with usage on stderr" {
    run --separate-stderr bash "$script" --unknown
    assert_failure 2
    assert_output ''
    assert_stderr --partial 'Usage:'
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "rejects extra arguments before running the demo" {
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/demo steps.yaml" extra
    assert_failure 2
    assert_output ''
    assert_stderr --partial 'Usage:'
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "rejects extra arguments after help" {
    run --separate-stderr bash "$script" --help extra
    assert_failure 2
    assert_output ''
    assert_stderr --partial 'Usage:'
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "reports missing YAML files without typing" {
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/missing.yaml"
    assert_failure 1
    assert_stderr
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "rejects malformed YAML without typing" {
    printf '%s\n' '- command: [' >"$BATS_TEST_TMPDIR/invalid.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
    assert_failure 1
    assert_stderr
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "validates all steps before typing any of them" {
    printf '%s\n' '- command: "echo valid"' '- command: 42' >"$BATS_TEST_TMPDIR/invalid.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/invalid.yaml"
    assert_failure 1
    assert_stderr
    assert_file_empty "$DEMO_TEST_LOG"
}

@test "accepts an empty demo without typing" {
    printf '[]\n' >"$BATS_TEST_TMPDIR/empty.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/empty.yaml"
    assert_success
    assert_output ''
    assert_stderr ''
    assert_file_empty "$DEMO_TEST_LOG"
}
