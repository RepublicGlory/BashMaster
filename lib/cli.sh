__bashmaster_list() {
    local directory name installed trusted enabled
    printf '%-16s %-10s %-10s %-10s %s\n' NAME INSTALLED TRUSTED ENABLED DESCRIPTION
    for directory in "$BASHMASTER_ROOT"/plugins/available/*; do
        [[ -d $directory ]] || continue
        name=${directory##*/}
        installed=yes
        trusted=no
        enabled=no
        __bashmaster_trusted "$name" && trusted=yes
        __bashmaster_enabled "$name" && enabled=yes
        if __bashmaster_manifest_validate "$directory" "$name"; then
            printf '%-16s %-10s %-10s %-10s %s\n' \
                "$name" "$installed" "$trusted" "$enabled" "${BM_MANIFEST[description]}"
        else
            printf '%-16s %-10s %-10s %-10s %s\n' "$name" "$installed" "$trusted" "$enabled" 'INVALID MANIFEST'
        fi
    done
}

__bashmaster_doctor() {
    local failed=0 item name link rc_file="$HOME/.bashrc"
    local -a required=(bin lib builtin config plugins cache logs docs)
    for item in "${required[@]}"; do
        if [[ ! -d $BASHMASTER_ROOT/$item || -L $BASHMASTER_ROOT/$item ]]; then
            __bashmaster_error "missing installation directory: $BASHMASTER_ROOT/$item"
            failed=1
        fi
    done
    for item in "$BASHMASTER_ROOT/plugins/available" "$BASHMASTER_ROOT/plugins/enabled"; do
        if [[ -L $item ]]; then
            __bashmaster_error "symlinked plugin state directory: $item"
            failed=1
        fi
    done
    [[ -x $BASHMASTER_ROOT/bin/bashmaster ]] || {
        __bashmaster_error 'bin/bashmaster is missing or not executable'
        failed=1
    }

    for item in "$BASHMASTER_ROOT"/plugins/available/*; do
        [[ -d $item ]] || continue
        name=${item##*/}
        if ! __bashmaster_manifest_validate "$item" "$name"; then
            failed=1
        fi
    done
    for link in "$BASHMASTER_ROOT"/plugins/enabled/*; do
        [[ -e $link || -L $link ]] || continue
        name=${link##*/}
        if ! __bashmaster_enabled "$name"; then
            __bashmaster_error "invalid enabled-plugin link: $link"
            failed=1
        elif ! __bashmaster_trusted "$name"; then
            __bashmaster_error "enabled plugin is not trusted: $name"
            failed=1
        fi
    done
    if [[ -f $rc_file ]]; then
        local starts ends
        starts=$(grep -Fxc '# >>> BashMaster >>>' "$rc_file" || :)
        ends=$(grep -Fxc '# <<< BashMaster <<<' "$rc_file" || :)
        if [[ $starts != "$ends" || ( $starts != 0 && $starts != 1 ) ]]; then
            __bashmaster_error 'malformed or duplicated BashMaster block in ~/.bashrc'
            failed=1
        elif [[ $starts == 1 ]] &&
             ! awk '
                $0 == "# >>> BashMaster >>>" { if (inside) bad = 1; inside = 1; next }
                $0 == "# <<< BashMaster <<<" { if (!inside) bad = 1; inside = 0; next }
                END { if (inside || bad) exit 1 }
             ' "$rc_file"; then
            __bashmaster_error 'unbalanced BashMaster block in ~/.bashrc'
            failed=1
        fi
    fi
    if (( failed )); then
        printf 'doctor: problems found\n'
        return 1
    fi
    printf 'doctor: OK\n'
}

__bashmaster_reload() {
    local name
    if [[ $- != *i* || ! -t 0 || ! -t 1 ]]; then
        __bashmaster_error 'reload requires an interactive TTY shell'
        return 1
    fi
    local -a loaded=("${__BASHMASTER_LOADED_NAMES[@]}")
    for name in "${loaded[@]}"; do
        __bashmaster_unload_plugin "$name"
    done
    __bashmaster_load_enabled
}

__bashmaster_run_plugin_command() {
    local command=$1 name function_name found=0
    shift
    for name in "${__BASHMASTER_LOADED_NAMES[@]}"; do
        __bashmaster_manifest_validate "$BASHMASTER_ROOT/plugins/available/$name" "$name" || return 1
        __bashmaster_manifest_declares commands "$command" || continue
        (( found == 0 )) || {
            __bashmaster_error "command '$command' is declared by multiple enabled plugins"
            return 1
        }
        found=1
        function_name="bm_${name}_command_${command}"
    done
    (( found == 1 )) || {
        __bashmaster_error "unknown command: $command"
        return 2
    }
    "$function_name" "$@"
}

__bashmaster_cli_main() {
    local operation=${1:-}
    [[ -n $operation ]] || {
        __bashmaster_error 'usage: bashmaster list|install|trust|enable|disable|remove|reload|doctor|COMMAND'
        return 2
    }
    shift
    case $operation in
        list)
            __bashmaster_list
            ;;
        install)
            [[ $# == 1 ]] || {
                __bashmaster_error 'usage: bashmaster install NAME|PLUGIN_DIR'
                return 2
            }
            if [[ -d $BASHMASTER_ROOT/builtin/$1 ]]; then
                __bashmaster_install_plugin "$BASHMASTER_ROOT/builtin/$1"
            else
                __bashmaster_install_plugin "$1"
            fi
            ;;
        trust)
            [[ $# == 1 ]] || {
                __bashmaster_error 'usage: bashmaster trust NAME'
                return 2
            }
            __bashmaster_trust "$1"
            ;;
        enable)
            [[ $# == 1 ]] || {
                __bashmaster_error 'usage: bashmaster enable NAME'
                return 2
            }
            __bashmaster_enable "$1"
            ;;
        disable)
            [[ $# == 1 ]] || {
                __bashmaster_error 'usage: bashmaster disable NAME'
                return 2
            }
            __bashmaster_disable "$1"
            ;;
        remove)
            [[ $# -ge 1 && $# -le 2 ]] || {
                __bashmaster_error 'usage: bashmaster remove NAME [--keep-trust]'
                return 2
            }
            local keep=0
            if [[ ${2:-} == --keep-trust ]]; then
                keep=1
            elif [[ $# == 2 ]]; then
                __bashmaster_error 'usage: bashmaster remove NAME [--keep-trust]'
                return 2
            fi
            __bashmaster_remove_plugin "$1" "$keep"
            ;;
        reload)
            [[ $# == 0 ]] || {
                __bashmaster_error 'usage: bashmaster reload'
                return 2
            }
            __bashmaster_reload
            ;;
        doctor)
            __bashmaster_doctor
            ;;
        uninstall)
            [[ $# -eq 0 || ${1:-} == --backup ]] || {
                __bashmaster_error 'usage: bashmaster uninstall [--backup]'
                return 2
            }
            local root=$BASHMASTER_ROOT
            local -a uninstall_args=(--install-dir "$root" --yes)
            [[ ${1:-} == --backup ]] && uninstall_args+=(--backup)
            __bashmaster_unload_all
            "$root/uninstall.sh" "${uninstall_args[@]}"
            local status=$?
            if (( status == 0 )); then
                __bashmaster_clear_runtime
            fi
            return "$status"
            ;;
        *)
            __bashmaster_run_plugin_command "$operation" "$@"
            ;;
    esac
}

__bashmaster_unload_all() {
    local name
    local -a loaded=("${__BASHMASTER_LOADED_NAMES[@]}")
    for name in "${loaded[@]}"; do
        __bashmaster_unload_plugin "$name"
    done
}

__bashmaster_clear_runtime() {
    local function_name
    __bashmaster_prompt_unregister
    while IFS= read -r function_name; do
        [[ -n $function_name ]] && unset -f "$function_name"
    done < <(compgen -A function __bashmaster_)
    unset -f bashmaster
    if [[ ${__BASHMASTER_ROOT_WAS_SET:-0} == 1 ]]; then
        BASHMASTER_ROOT=$__BASHMASTER_PREVIOUS_ROOT
        export BASHMASTER_ROOT
    else
        unset BASHMASTER_ROOT
    fi
    unset __BASHMASTER_ROOT_WAS_SET __BASHMASTER_PREVIOUS_ROOT
    unset __BASHMASTER_INITIALIZED
    unset __BASHMASTER_LOADED __BASHMASTER_LOADED_NAMES
    unset __BASHMASTER_PROMPT_INSTALLED __BASHMASTER_PROMPT_ARRAY
    unset __BASHMASTER_PROMPT_PREVIOUS __BASHMASTER_PROMPT_ADDED
    unset BM_MANIFEST BM_CSV_ITEMS BM_CONFIG_VALUE
    unset BM_QUICKBAR_LABELS BM_QUICKBAR_COMMANDS BM_QUICKBAR_TRUNCATED
}
