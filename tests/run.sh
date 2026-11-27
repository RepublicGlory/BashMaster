#!/usr/bin/env bash
set -euo pipefail

REPOSITORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

assert_not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "did not expect '$2' in $1"
    fi
}

TEST_HOME="$TEST_DIR/home"
INSTALL_ROOT="$TEST_DIR/install root"
mkdir -p "$TEST_HOME"
printf 'export USER_CUSTOM_SETTING=kept\n' > "$TEST_HOME/.bashrc"
cp -p "$TEST_HOME/.bashrc" "$TEST_DIR/rc.original"

HOME=$TEST_HOME "$REPOSITORY/install.sh" --install-dir "$INSTALL_ROOT" --yes > "$TEST_DIR/install.out"
assert_contains "$TEST_HOME/.bashrc" 'export USER_CUSTOM_SETTING=kept'
[[ $(grep -Fxc '# >>> BashMaster >>>' "$TEST_HOME/.bashrc") == 1 ]] || fail 'expected one start marker'
[[ $(grep -Fxc '# <<< BashMaster <<<' "$TEST_HOME/.bashrc") == 1 ]] || fail 'expected one end marker'
[[ -f $INSTALL_ROOT/plugins/available/splash/plugin.conf ]] || fail 'bundled splash not installed'
[[ -f $INSTALL_ROOT/config/quickbar/config.conf ]] || fail 'quickbar config was not materialized'
[[ ! -f $INSTALL_ROOT/config/trusted.list || ! -s $INSTALL_ROOT/config/trusted.list ]] ||
    fail 'plugins must not be trusted at install time'
backup_count=$(find "$TEST_HOME" -maxdepth 1 -name '.bashrc.bashmaster.*.bak' | wc -l)
[[ $backup_count == 1 ]] || fail 'expected a timestamped rc backup'

HOME=$TEST_HOME "$REPOSITORY/install.sh" --install-dir "$INSTALL_ROOT" --yes > "$TEST_DIR/reinstall.out"
[[ $(grep -Fxc '# >>> BashMaster >>>' "$TEST_HOME/.bashrc") == 1 ]] || fail 'install is not idempotent'
[[ $(find "$TEST_HOME" -maxdepth 1 -name '.bashrc.bashmaster.*.bak' | wc -l) == "$backup_count" ]] ||
    fail 'unchanged rc should not be backed up again'

assert_contains "$INSTALL_ROOT/plugins/available/splash/plugin.conf" 'name=splash'
if BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" enable splash >"$TEST_DIR/enable.out" 2>&1; then
    fail 'untrusted plugin was enabled'
fi
[[ ! -L $INSTALL_ROOT/plugins/enabled/splash ]] || fail 'untrusted plugin left an enabled link'

mkdir -p "$TEST_DIR/probe"
cat > "$TEST_DIR/probe/plugin.conf" <<'EOF'
name=probe
version=1.0.0
description=Lifecycle test probe
hooks=on_load,on_unload,on_prompt
commands=ping
EOF
cat > "$TEST_DIR/probe/plugin.sh" <<'EOF'
mkdir -p "$BASHMASTER_ROOT/config/probe"
printf 'sourced\n' > "$BASHMASTER_ROOT/config/probe/sourced"
bm_probe_on_load() {
    printf 'loaded\n' > "$BASHMASTER_ROOT/config/probe/loaded"
}
bm_probe_on_unload() {
    printf 'unloaded\n' >> "$BASHMASTER_ROOT/config/probe/loaded"
}
bm_probe_on_prompt() {
    printf 'prompt\n' >> "$BASHMASTER_ROOT/config/probe/prompts"
}
bm_probe_command_ping() {
    printf 'PONG\n'
}
bm_probe_command_hidden() {
    printf 'NOT DECLARED\n'
}
EOF
mkdir -p "$TEST_DIR/invalid"
cat > "$TEST_DIR/invalid/plugin.conf" <<'EOF'
name=invalid
name=invalid
version=1.0.0
description=Must be rejected
hooks=
commands=
EOF
printf 'printf sourced > "$BASHMASTER_ROOT/config/invalid-sourced"\n' > "$TEST_DIR/invalid/plugin.sh"
if BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" install "$TEST_DIR/invalid" \
    > "$TEST_DIR/invalid-install.out" 2>&1; then
    fail 'plugin with a duplicate manifest key was installed'
fi
[[ ! -e $INSTALL_ROOT/plugins/available/invalid ]] || fail 'invalid manifest left installed files'

if BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" install "$TEST_DIR/probe" >"$TEST_DIR/probe-install.out" 2>&1; then
    :
else
    fail 'valid external plugin could not be installed'
fi
if BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" enable probe >"$TEST_DIR/probe-enable.out" 2>&1; then
    fail 'untrusted plugin was enabled'
fi
[[ ! -e $INSTALL_ROOT/config/probe/sourced ]] || fail 'untrusted plugin was sourced'

BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" trust splash
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" enable splash >"$TEST_DIR/splash-enable.out"
[[ ! -s $TEST_DIR/splash-enable.out ]] || fail 'non-interactive enable loaded the splash plugin'
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" trust probe
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" enable probe
[[ ! -e $INSTALL_ROOT/config/probe/sourced ]] || fail 'non-interactive enable sourced a plugin'
if BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" reload > "$TEST_DIR/noninteractive-reload.out" 2>&1; then
    fail 'non-interactive reload was allowed to load plugins'
fi
assert_contains "$TEST_DIR/noninteractive-reload.out" 'reload requires an interactive TTY shell'
[[ ! -e $INSTALL_ROOT/config/probe/sourced ]] || fail 'non-interactive reload sourced a plugin'

if ! command -v script >/dev/null 2>&1; then
    fail 'util-linux script is required for the interactive startup test'
fi
cat > "$TEST_DIR/interactive.commands" <<'EOF'
if [[ $(type -t bashmaster) == function && $(type -t bm_probe_command_ping) == function ]]; then echo FUNCTIONS_OK; fi
bashmaster ping
if bashmaster splash; then echo MANUAL_SPLASH_OK; fi
if bashmaster hidden >/dev/null 2>&1; then echo WRONG; else echo DECLARATION_GATE_OK; fi
exit
EOF
script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/interactive.commands" > "$TEST_DIR/interactive.out" 2>&1
assert_contains "$TEST_DIR/interactive.out" 'PONG'
assert_contains "$TEST_DIR/interactive.out" 'MANUAL_SPLASH_OK'
assert_contains "$TEST_DIR/interactive.out" 'DECLARATION_GATE_OK'
assert_contains "$TEST_DIR/interactive.out" 'FUNCTIONS_OK'
assert_contains "$TEST_DIR/interactive.out" 'BASHMASTER'
[[ -f $INSTALL_ROOT/config/probe/sourced ]] || fail 'trusted plugin did not load in interactive tty'
[[ -f $INSTALL_ROOT/config/probe/loaded ]] || fail 'on_load hook did not run'
[[ -f $INSTALL_ROOT/config/probe/prompts ]] || fail 'on_prompt hook did not run'

BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" list > "$TEST_DIR/list.out"
assert_contains "$TEST_DIR/list.out" 'quickbar'
assert_contains "$TEST_DIR/list.out" 'splash'
assert_contains "$TEST_DIR/list.out" 'probe'

BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" trust quickbar
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" enable quickbar
cat > "$INSTALL_ROOT/config/splash/config.conf" <<'EOF'
enabled=0
show_user=0
show_host=0
show_time=0
show_os=0
EOF
printf 'bashmaster splash && echo SPLASH_MANUAL_OK\nexit\n' > "$TEST_DIR/splash.commands"
timeout 10s script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/splash.commands" > "$TEST_DIR/splash.out" 2>&1
assert_contains "$TEST_DIR/splash.out" 'SPLASH_MANUAL_OK'
[[ $(grep -Fc 'BASHMASTER' "$TEST_DIR/splash.out") == 1 ]] ||
    fail 'splash startup switch or manual command behaved incorrectly'
assert_not_contains "$TEST_DIR/splash.out" 'User:'
cp -- "$REPOSITORY/config/splash.conf.example" "$INSTALL_ROOT/config/splash/config.conf"

cat > "$INSTALL_ROOT/config/quickbar/config.conf" <<'EOF'
First|printf 'QBAR_FIRST\n'
Second|printf 'QBAR_SECOND\n'
EOF
printf 'bashmaster quickbar\n\033[B\r\nexit\n' > "$TEST_DIR/quickbar.commands"
timeout 10s script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/quickbar.commands" > "$TEST_DIR/quickbar.out" 2>&1
assert_contains "$TEST_DIR/quickbar.out" 'QBAR_SECOND'

printf 'bashmaster quickbar\n\033[B\033[A\r\nexit\n' > "$TEST_DIR/quickbar-up.commands"
timeout 10s script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/quickbar-up.commands" > "$TEST_DIR/quickbar-up.out" 2>&1
assert_contains "$TEST_DIR/quickbar-up.out" 'QBAR_FIRST'

printf 'bashmaster quickbar\nqexit\n' > "$TEST_DIR/quickbar-quit.commands"
timeout 10s script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/quickbar-quit.commands" > "$TEST_DIR/quickbar-quit.out" 2>&1
assert_not_contains "$TEST_DIR/quickbar-quit.out" 'QBAR_FIRST'
assert_not_contains "$TEST_DIR/quickbar-quit.out" 'QBAR_SECOND'

printf 'bashmaster quickbar\n\033qexit\n' > "$TEST_DIR/quickbar-escape.commands"
timeout 10s script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/quickbar-escape.commands" > "$TEST_DIR/quickbar-escape.out" 2>&1
assert_not_contains "$TEST_DIR/quickbar-escape.out" 'QBAR_FIRST'
assert_not_contains "$TEST_DIR/quickbar-escape.out" 'QBAR_SECOND'

{
    for ((i = 1; i <= 12; i++)); do
        printf 'Item%02d|printf ignored\n' "$i"
    done
} > "$INSTALL_ROOT/config/quickbar/config.conf"
fallback_output=$(BASHMASTER_ROOT=$INSTALL_ROOT bash -c '
    source "$BASHMASTER_ROOT/lib/common.sh"
    source "$BASHMASTER_ROOT/lib/config.sh"
    source "$BASHMASTER_ROOT/lib/ui.sh"
    source "$BASHMASTER_ROOT/plugins/available/quickbar/plugin.sh"
    bm_quickbar_command_quickbar
')
[[ $(printf '%s\n' "$fallback_output" | grep -cE '^[[:space:]]*[0-9]+\.') == 10 ]] ||
    fail 'quickbar fallback did not cap display at 10 entries'
assert_contains <(printf '%s\n' "$fallback_output") 'Only the first 10 entries are shown.'

noninteractive_output=$(HOME=$TEST_HOME bash --noprofile -c \
    'source "$HOME/.bashrc"; printf NONINTERACTIVE_OK')
[[ $noninteractive_output == NONINTERACTIVE_OK ]] || fail 'non-interactive shell emitted plugin output'

BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" doctor > "$TEST_DIR/doctor.out"
assert_contains "$TEST_DIR/doctor.out" 'doctor: OK'
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" disable probe
[[ ! -e $INSTALL_ROOT/plugins/enabled/probe ]] || fail 'disable did not remove the enabled link'
assert_contains "$INSTALL_ROOT/config/trusted.list" 'probe'
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" remove probe --keep-trust
[[ ! -e $INSTALL_ROOT/plugins/available/probe ]] || fail 'remove left installed plugin files'
assert_contains "$INSTALL_ROOT/config/trusted.list" 'probe'
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" install "$TEST_DIR/probe"
assert_contains "$INSTALL_ROOT/config/trusted.list" 'probe'
BASHMASTER_ROOT=$INSTALL_ROOT "$INSTALL_ROOT/bin/bashmaster" remove probe
assert_not_contains "$INSTALL_ROOT/config/trusted.list" 'probe'
assert_contains "$INSTALL_ROOT/logs/audit.log" 'action=trust plugin=probe'
assert_contains "$INSTALL_ROOT/logs/audit.log" 'action=enable plugin=probe'
assert_contains "$INSTALL_ROOT/logs/audit.log" 'action=disable plugin=probe'
assert_contains "$INSTALL_ROOT/logs/audit.log" 'action=remove plugin=probe'

HOME=$TEST_HOME "$REPOSITORY/uninstall.sh" --install-dir "$INSTALL_ROOT" --yes --backup > "$TEST_DIR/uninstall.out"
[[ ! -e $INSTALL_ROOT ]] || fail 'uninstaller left the installation root'
assert_not_contains "$TEST_HOME/.bashrc" '# >>> BashMaster >>>'
[[ -n $(find "$TEST_DIR" -maxdepth 1 -name 'install root.backup.*.tar.gz' -print -quit) ]] ||
    fail 'requested config backup was not retained'
cmp -s "$TEST_HOME/.bashrc" "$TEST_DIR/rc.original" || fail 'uninstall did not restore rc bytes exactly'

CURRENT_ROOT="$TEST_DIR/current-shell"
HOME=$TEST_HOME "$REPOSITORY/install.sh" --install-dir "$CURRENT_ROOT" --yes > /dev/null
BASHMASTER_ROOT=$CURRENT_ROOT "$CURRENT_ROOT/bin/bashmaster" install "$TEST_DIR/probe"
BASHMASTER_ROOT=$CURRENT_ROOT "$CURRENT_ROOT/bin/bashmaster" trust probe
BASHMASTER_ROOT=$CURRENT_ROOT "$CURRENT_ROOT/bin/bashmaster" enable probe
cat > "$TEST_DIR/uninstall.commands" <<'EOF'
bashmaster disable probe
cat "$BASHMASTER_ROOT/config/probe/loaded"
bashmaster enable probe
bashmaster uninstall
if declare -F bashmaster >/dev/null; then echo FUNCTION_LEFT; else echo FUNCTION_CLEANED; fi
if [[ -v BASHMASTER_ROOT ]]; then echo ROOT_ENV_LEFT; else echo ENV_CLEANED; fi
if [[ ${PROMPT_COMMAND:-} == *__bashmaster_prompt_dispatch* ]]; then echo PROMPT_LEFT; else echo PROMPT_CLEANED; fi
exit
EOF
script -qec "env HOME='$TEST_HOME' bash --noprofile --rcfile '$TEST_HOME/.bashrc' -i" \
    /dev/null < "$TEST_DIR/uninstall.commands" > "$TEST_DIR/current-uninstall.out" 2>&1
[[ ! -e $CURRENT_ROOT ]] || fail 'bashmaster uninstall left its root'
assert_contains "$TEST_DIR/current-uninstall.out" 'FUNCTION_CLEANED'
assert_contains "$TEST_DIR/current-uninstall.out" 'ENV_CLEANED'
assert_contains "$TEST_DIR/current-uninstall.out" 'PROMPT_CLEANED'
assert_contains "$TEST_DIR/current-uninstall.out" 'unloaded'
assert_not_contains "$TEST_HOME/.bashrc" '# >>> BashMaster >>>'
cmp -s "$TEST_HOME/.bashrc" "$TEST_DIR/rc.original" || fail 'interactive uninstall changed unrelated rc bytes'

NO_RC_ROOT="$TEST_DIR/no-rc-install"
original_rc=$(<"$TEST_HOME/.bashrc")
HOME=$TEST_HOME "$REPOSITORY/install.sh" --install-dir "$NO_RC_ROOT" --yes --no-bashrc > /dev/null
[[ $(<"$TEST_HOME/.bashrc") == "$original_rc" ]] || fail '--no-bashrc modified the user rc'
HOME=$TEST_HOME "$REPOSITORY/uninstall.sh" --install-dir "$NO_RC_ROOT" --yes > /dev/null
[[ $(<"$TEST_HOME/.bashrc") == "$original_rc" ]] || fail 'uninstall changed rc without an injected block'

NO_NEWLINE_HOME="$TEST_DIR/no-newline-home"
NO_NEWLINE_ROOT="$TEST_DIR/no-newline-root"
mkdir -p "$NO_NEWLINE_HOME"
printf 'export KEEP_WITHOUT_NEWLINE=1' > "$NO_NEWLINE_HOME/.bashrc"
cp -p "$NO_NEWLINE_HOME/.bashrc" "$TEST_DIR/no-newline.original"
HOME=$NO_NEWLINE_HOME "$REPOSITORY/install.sh" --install-dir "$NO_NEWLINE_ROOT" --yes > /dev/null
HOME=$NO_NEWLINE_HOME "$REPOSITORY/uninstall.sh" --install-dir "$NO_NEWLINE_ROOT" --yes > /dev/null
cmp -s "$NO_NEWLINE_HOME/.bashrc" "$TEST_DIR/no-newline.original" ||
    fail 'uninstall changed the original final-newline state'

MALFORMED_HOME="$TEST_DIR/malformed-home"
MALFORMED_ROOT="$TEST_DIR/malformed-root"
mkdir -p "$MALFORMED_HOME"
printf 'user data\n# >>> BashMaster >>>\n' > "$MALFORMED_HOME/.bashrc"
cp -p "$MALFORMED_HOME/.bashrc" "$TEST_DIR/malformed.original"
if HOME=$MALFORMED_HOME "$REPOSITORY/install.sh" --install-dir "$MALFORMED_ROOT" --yes \
    > "$TEST_DIR/malformed.out" 2>&1; then
    fail 'installer accepted a malformed marked block'
fi
[[ ! -e $MALFORMED_ROOT ]] || fail 'installer created a root despite invalid rc markers'
cmp -s "$MALFORMED_HOME/.bashrc" "$TEST_DIR/malformed.original" ||
    fail 'installer modified malformed user rc content'

ROLLBACK_HOME="$TEST_DIR/rollback-home"
ROLLBACK_ROOT="$TEST_DIR/rollback-root"
mkdir -p "$ROLLBACK_HOME"
printf 'user data\n' > "$ROLLBACK_HOME/.bashrc"
HOME=$ROLLBACK_HOME "$REPOSITORY/install.sh" --install-dir "$ROLLBACK_ROOT" --yes > /dev/null
sed 's/^# >>> BashMaster >>>$/# >>> BashMaster damaged >>>/' \
    "$ROLLBACK_HOME/.bashrc" > "$TEST_DIR/rollback.rc"
cp -- "$TEST_DIR/rollback.rc" "$ROLLBACK_HOME/.bashrc"
if HOME=$ROLLBACK_HOME "$REPOSITORY/uninstall.sh" --install-dir "$ROLLBACK_ROOT" --yes \
    > "$TEST_DIR/rollback-uninstall.out" 2>&1; then
    fail 'uninstaller accepted malformed rc markers'
fi
[[ -d $ROLLBACK_ROOT ]] || fail 'uninstaller did not restore root after rc validation failure'
cmp -s "$ROLLBACK_HOME/.bashrc" "$TEST_DIR/rollback.rc" ||
    fail 'uninstaller modified malformed rc content'
[[ -z $(find "$TEST_DIR" -maxdepth 1 -name 'rollback-root.uninstall.*' -print -quit) ]] ||
    fail 'uninstaller left a staging directory after rollback'

printf 'All BashMaster tests passed.\n'
