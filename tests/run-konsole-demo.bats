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
cat >>"$DEMO_TEST_LOG"
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
printf 'tab %s %s %s\n' "$@" >>"$DEMO_TEST_LOG"
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
}

run_without_tool()
{
    local missing=$1 tool tool_bin=$BATS_TEST_TMPDIR/without-$1
    shift
    mkdir "$tool_bin"
    for tool in bash cat dotool sleep; do
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
    for tool in dotool yq; do
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
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'type  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\nsleep 0.5'
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
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'type  # Preparing the demo\nkey enter\nsleep 0.25\ntype  # Existing comment\nkey enter\nsleep 0.5\ntype echo hello\nkey enter\nsleep 0.25\ntype  # Finished: ready\nkey enter\nsleep 0.25'
}

@test "accepts empty and quoted numeric string steps as comments" {
    printf '%s\n' '- ""' '- "42"' >"$BATS_TEST_TMPDIR/strings.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/strings.yaml"
    assert_success
    assert_output ''
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'type  # \nkey enter\nsleep 0.25\ntype  # 42\nkey enter\nsleep 0.25'
}

@test "uses ten seconds for string steps when the default delay is unset" {
    unset KONSOLE_DEMO_DEFAULT_SLEEP
    printf '%s\n' '- Preparing the demo' >"$BATS_TEST_TMPDIR/strings.yaml"
    run --separate-stderr bash "$script" "$BATS_TEST_TMPDIR/strings.yaml"
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'type  # Preparing the demo\nkey enter\nsleep 10'
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

@test "opens a Konsole tab before typing with -t" {
    run --separate-stderr bash "$script" -t "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'tab org.kde.konsole.test /Windows/1 org.kde.konsole.Window.newSession\ntype  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\nsleep 0.5'
}

@test "opens a Yakuake tab before typing with -t" {
    export DEMO_TEST_TERMINAL=yakuake
    run --separate-stderr bash "$script" -t "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'tab org.kde.yakuake /yakuake/sessions org.kde.yakuake.addSession\ntype  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\nsleep 0.5'
}

@test "stops before typing when opening a tab fails" {
    export DEMO_TEST_TAB_STATUS=7
    run --separate-stderr bash "$script" -t "$BATS_TEST_TMPDIR/demo steps.yaml"
    assert_failure 7
    assert_equal "$(cat "$DEMO_TEST_LOG")" 'tab org.kde.konsole.test /Windows/1 org.kde.konsole.Window.newSession'
}

@test "shows help with -t without opening a tab" {
    for option in -h --help; do
        run --separate-stderr bash "$script" -t "$option"
        assert_success
        assert_output --partial '-t'
        assert_stderr ''
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "rejects invalid arguments with -t before opening a tab" {
    run --separate-stderr bash "$script" -t
    assert_failure 2
    assert_stderr --partial 'Usage:'
    assert_file_empty "$DEMO_TEST_LOG"

    run --separate-stderr bash "$script" -t "$BATS_TEST_TMPDIR/demo steps.yaml" extra
    assert_failure 2
    assert_stderr --partial 'Usage:'
    assert_file_empty "$DEMO_TEST_LOG"

    for option in -x --unknown; do
        run --separate-stderr bash "$script" -t "$option" "$BATS_TEST_TMPDIR/demo steps.yaml"
        assert_failure 2
        assert_stderr --partial 'Unknown option:'
        assert_file_empty "$DEMO_TEST_LOG"
    done
}

@test "accepts a filename beginning with a dash after --" {
    cp "$BATS_TEST_TMPDIR/demo steps.yaml" "$BATS_TEST_TMPDIR/-t"
    cd "$BATS_TEST_TMPDIR" || return
    run --separate-stderr bash "$script" -- -t
    assert_success
    assert_stderr ''
    assert_equal "$(cat "$DEMO_TEST_LOG")" $'type  # Preparing the demo\nkey enter\nsleep 0.25\ntype echo hello\nkey enter\nsleep 0.5'
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
