#!/usr/bin/env bats

setup()
{
    bats_load_library bats-support
    bats_load_library bats-assert
    bats_load_library bats-file
    cd "$BATS_TEST_DIRNAME/.." || return
}

@test "installs the demo to usr/bin by default with mode 0755 and no extension" {
    run env -u BINDIR XDG_BIN_HOME='/ignored user bin' DESTDIR="$BATS_TEST_TMPDIR/stage" bash install.sh --system
    assert_success
    installed=$BATS_TEST_TMPDIR/stage/usr/bin/run-konsole-demo
    assert_file_executable "$installed"
    assert_file_permission 755 "$installed"
    assert_file_not_exists "$installed.sh"
    run cmp run-konsole-demo.sh "$installed"
    assert_success
    run "$installed" --help
    assert_success
    assert_output --partial 'Usage:'
}

@test "honors BINDIR containing spaces and DESTDIR" {
    run env BINDIR='/custom bin' DESTDIR="$BATS_TEST_TMPDIR/stage" bash install.sh --system
    assert_success
    installed="$BATS_TEST_TMPDIR/stage/custom bin/run-konsole-demo"
    assert_file_executable "$installed"
    assert_file_permission 755 "$installed"
    assert_file_not_exists "$BATS_TEST_TMPDIR/stage/usr/bin/run-konsole-demo"
}

@test "user installation defaults to HOME/.local/bin" {
    run env -u BINDIR -u XDG_BIN_HOME DESTDIR="$BATS_TEST_TMPDIR/stage" bash install.sh --user
    assert_success
    installed=$BATS_TEST_TMPDIR/stage$HOME/.local/bin/run-konsole-demo
    assert_file_executable "$installed"
    assert_file_permission 755 "$installed"
    assert_file_not_exists "$BATS_TEST_TMPDIR/stage/usr/bin/run-konsole-demo"
}

@test "user installation honors XDG_BIN_HOME" {
    run env -u BINDIR XDG_BIN_HOME='/user bin' DESTDIR="$BATS_TEST_TMPDIR/stage" bash install.sh --user
    assert_success
    assert_file_executable "$BATS_TEST_TMPDIR/stage/user bin/run-konsole-demo"
    assert_file_not_exists "$BATS_TEST_TMPDIR/stage/usr/bin/run-konsole-demo"
}

@test "explicit BINDIR overrides XDG_BIN_HOME for user installation" {
    run env BINDIR='/custom bin' XDG_BIN_HOME='/user bin' DESTDIR="$BATS_TEST_TMPDIR/stage" bash install.sh --user
    assert_success
    assert_file_executable "$BATS_TEST_TMPDIR/stage/custom bin/run-konsole-demo"
    assert_file_not_exists "$BATS_TEST_TMPDIR/stage/user bin/run-konsole-demo"
}
