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
    chmod +x "$BATS_TEST_TMPDIR/bin/dotool" "$BATS_TEST_TMPDIR/bin/sleep"
    export PATH=$BATS_TEST_TMPDIR/bin:$PATH

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
