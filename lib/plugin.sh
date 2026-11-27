declare -gA __BASHMASTER_LOADED=()
declare -ga __BASHMASTER_LOADED_NAMES=()
declare -g __BASHMASTER_PROMPT_INSTALLED=0
declare -g __BASHMASTER_PROMPT_ARRAY=0
declare -g __BASHMASTER_PROMPT_PREVIOUS=
declare -g __BASHMASTER_PROMPT_ADDED=

__bashmaster_trusted() {
    local name=$1
    [[ ! -L $BASHMASTER_ROOT/config &&
       ! -L $BASHMASTER_ROOT/config/trusted.list &&
       -f $BASHMASTER_ROOT/config/trusted.list ]] &&
        grep -Fqx -- "$name" "$BASHMASTER_ROOT/config/trusted.list"
}

__bashmaster_plugin_store_safe() {
    local path
    for path in \
        "$BASHMASTER_ROOT/plugins" \
        "$BASHMASTER_ROOT/plugins/available" \
        "$BASHMASTER_ROOT/plugins/enabled"; do
        if [[ -L $path ]]; then
            __bashmaster_error "refusing a symlinked plugin state path: $path"
            return 1
        fi
    done
    return 0
}

__bashmaster_installed() {
    __bashmaster_plugin_store_safe || return 1
    local name=$1
    [[ -d $BASHMASTER_ROOT/plugins/available/$name &&
       ! -L $BASHMASTER_ROOT/plugins/available/$name ]]
}

__bashmaster_enabled() {
    local name=$1 link="$BASHMASTER_ROOT/plugins/enabled/$1"
    [[ -L $link ]] && [[ $(readlink -- "$link") == "../available/$name" ]]
}

__bashmaster_prompt_register() {
    [[ $__BASHMASTER_PROMPT_INSTALLED == 1 ]] && return 0
    local declaration
    declaration=$(declare -p PROMPT_COMMAND 2>/dev/null || :)
    if [[ $declaration == *"declare -a"* ]]; then
        local item
        for item in "${PROMPT_COMMAND[@]}"; do
            [[ $item == __bashmaster_prompt_dispatch ]] && return 0
        done
        PROMPT_COMMAND+=(__bashmaster_prompt_dispatch)
        __BASHMASTER_PROMPT_ARRAY=1
    else
        if [[ ${PROMPT_COMMAND:-} == __bashmaster_prompt_dispatch ||
              ${PROMPT_COMMAND:-} == *'; __bashmaster_prompt_dispatch' ]]; then
            return 0
        fi
        if [[ -n ${PROMPT_COMMAND:-} ]]; then
            __BASHMASTER_PROMPT_PREVIOUS=$PROMPT_COMMAND
            PROMPT_COMMAND+='; __bashmaster_prompt_dispatch'
        else
            __BASHMASTER_PROMPT_PREVIOUS=
            PROMPT_COMMAND=__bashmaster_prompt_dispatch
        fi
        __BASHMASTER_PROMPT_ADDED=$PROMPT_COMMAND
        __BASHMASTER_PROMPT_ARRAY=0
    fi
    __BASHMASTER_PROMPT_INSTALLED=1
}

__bashmaster_prompt_unregister() {
    [[ $__BASHMASTER_PROMPT_INSTALLED == 1 ]] || return 0
    if [[ $__BASHMASTER_PROMPT_ARRAY == 1 ]]; then
        local -a remaining=()
        local item
        for item in "${PROMPT_COMMAND[@]}"; do
            [[ $item == __bashmaster_prompt_dispatch ]] || remaining+=("$item")
        done
        PROMPT_COMMAND=("${remaining[@]}")
    else
        if [[ ${PROMPT_COMMAND:-} == "$__BASHMASTER_PROMPT_ADDED" ]]; then
            PROMPT_COMMAND=$__BASHMASTER_PROMPT_PREVIOUS
        else
            PROMPT_COMMAND=${PROMPT_COMMAND//'; __bashmaster_prompt_dispatch'/}
            PROMPT_COMMAND=${PROMPT_COMMAND#__bashmaster_prompt_dispatch'; '}
            PROMPT_COMMAND=${PROMPT_COMMAND%; __bashmaster_prompt_dispatch}
        fi
    fi
    __BASHMASTER_PROMPT_INSTALLED=0
    __BASHMASTER_PROMPT_ARRAY=0
    __BASHMASTER_PROMPT_PREVIOUS=
    __BASHMASTER_PROMPT_ADDED=
}

__bashmaster_refresh_prompt_registration() {
    local name
    for name in "${__BASHMASTER_LOADED_NAMES[@]}"; do
        if __bashmaster_manifest_validate "$BASHMASTER_ROOT/plugins/available/$name" "$name" &&
           __bashmaster_manifest_declares hooks on_prompt; then
            __bashmaster_prompt_register
            return 0
        fi
    done
    __bashmaster_prompt_unregister
}

__bashmaster_remove_plugin_functions() {
    local name=$1 function_name
    while IFS= read -r function_name; do
        [[ -n $function_name ]] && unset -f "$function_name"
    done < <(compgen -A function "bm_${name}_")
}

__bashmaster_plugin_hook() {
    local name=$1 hook=$2 function_name="bm_${1}_${2}"
    __bashmaster_manifest_validate "$BASHMASTER_ROOT/plugins/available/$name" "$name" || return 1
    __bashmaster_manifest_declares hooks "$hook" || return 0
    declare -F "$function_name" >/dev/null || {
        __bashmaster_error "plugin '$name' declares missing hook '$hook'"
        return 1
    }
    "$function_name"
}

__bashmaster_unload_plugin() {
    local name=$1
    [[ ${__BASHMASTER_LOADED[$name]+yes} ]] || return 0
    if ! __bashmaster_plugin_hook "$name" on_unload; then
        __bashmaster_error "plugin '$name' on_unload hook failed"
    fi
    __bashmaster_remove_plugin_functions "$name"
    unset "__BASHMASTER_LOADED[$name]"
    local -a remaining=()
    local loaded
    for loaded in "${__BASHMASTER_LOADED_NAMES[@]}"; do
        [[ $loaded == "$name" ]] || remaining+=("$loaded")
    done
    __BASHMASTER_LOADED_NAMES=("${remaining[@]}")
    __bashmaster_refresh_prompt_registration
}

__bashmaster_load_plugin() {
    local name=$1 directory="$BASHMASTER_ROOT/plugins/available/$1"
    local command function_name
    [[ ${__BASHMASTER_LOADED[$name]+yes} ]] && return 0
    __bashmaster_trusted "$name" || {
        __bashmaster_error "plugin '$name' is not trusted; refusing to load"
        return 1
    }
    __bashmaster_manifest_validate "$directory" "$name" || return 1

    # The source operation is the trust boundary: only a validated, trusted package reaches it.
    if ! source "$directory/plugin.sh"; then
        __bashmaster_remove_plugin_functions "$name"
        __bashmaster_error "failed to source plugin '$name'"
        return 1
    fi
    if ! __bashmaster_manifest_validate "$directory" "$name"; then
        __bashmaster_remove_plugin_functions "$name"
        return 1
    fi
    __bashmaster_split_csv "${BM_MANIFEST[commands]}" || return 1
    for command in "${BM_CSV_ITEMS[@]}"; do
        function_name="bm_${name}_command_${command}"
        if ! declare -F "$function_name" >/dev/null; then
            __bashmaster_remove_plugin_functions "$name"
            __bashmaster_error "plugin '$name' is missing declared command '$command'"
            return 1
        fi
    done
    __bashmaster_split_csv "${BM_MANIFEST[hooks]}" || return 1
    for command in "${BM_CSV_ITEMS[@]}"; do
        function_name="bm_${name}_${command}"
        if ! declare -F "$function_name" >/dev/null; then
            __bashmaster_remove_plugin_functions "$name"
            __bashmaster_error "plugin '$name' is missing declared hook '$command'"
            return 1
        fi
    done

    __BASHMASTER_LOADED[$name]=1
    __BASHMASTER_LOADED_NAMES+=("$name")
    if ! __bashmaster_plugin_hook "$name" on_load; then
        __bashmaster_unload_plugin "$name"
        __bashmaster_error "plugin '$name' on_load hook failed"
        return 1
    fi
    __bashmaster_manifest_validate "$directory" "$name" || return 1
    __bashmaster_refresh_prompt_registration
}

__bashmaster_load_enabled() {
    local link name
    __bashmaster_plugin_store_safe || return 1
    for link in "$BASHMASTER_ROOT"/plugins/enabled/*; do
        [[ -L $link ]] || continue
        name=${link##*/}
        if ! __bashmaster_valid_name "$name" || ! __bashmaster_enabled "$name"; then
            __bashmaster_error "invalid enabled-plugin link: $link"
            continue
        fi
        __bashmaster_load_plugin "$name" || :
    done
}

__bashmaster_prompt_dispatch() {
    local previous_status=$? name
    for name in "${__BASHMASTER_LOADED_NAMES[@]}"; do
        if __bashmaster_plugin_hook "$name" on_prompt; then
            :
        else
            __bashmaster_error "plugin '$name' on_prompt hook failed"
        fi
    done
    return "$previous_status"
}

__bashmaster_enable() {
    local name=$1 link="$BASHMASTER_ROOT/plugins/enabled/$1" temporary
    __bashmaster_valid_name "$name" || {
        __bashmaster_error "invalid plugin name: $name"
        return 2
    }
    __bashmaster_plugin_store_safe || return 1
    __bashmaster_installed "$name" || {
        __bashmaster_error "plugin '$name' is not installed"
        return 1
    }
    __bashmaster_trusted "$name" || {
        __bashmaster_error "plugin '$name' must be trusted before enabling"
        return 1
    }
    __bashmaster_manifest_validate "$BASHMASTER_ROOT/plugins/available/$name" "$name" || return 1
    mkdir -p -- "$BASHMASTER_ROOT/plugins/enabled"
    if __bashmaster_enabled "$name"; then
        if [[ $- == *i* && -t 0 && -t 1 ]]; then
            __bashmaster_load_plugin "$name"
        fi
        return 0
    fi
    [[ ! -e $link && ! -L $link ]] || {
        __bashmaster_error "enabled-plugin path already exists and is not managed: $link"
        return 1
    }
    temporary="$link.tmp.$$"
    ln -s -- "../available/$name" "$temporary" || return 1
    if ! mv -- "$temporary" "$link"; then
        rm -f -- "$temporary"
        return 1
    fi
    if ! __bashmaster_audit enable "$name"; then
        rm -- "$link"
        __bashmaster_error "could not audit enabling plugin '$name'; enable was rolled back"
        return 1
    fi
    if [[ $- == *i* && -t 0 && -t 1 ]]; then
        if ! __bashmaster_load_plugin "$name"; then
            rm -- "$link"
            __bashmaster_audit disable "$name" || :
            __bashmaster_error "plugin '$name' failed to load; enable was rolled back"
            return 1
        fi
    fi
}

__bashmaster_disable() {
    local name=$1 link="$BASHMASTER_ROOT/plugins/enabled/$1"
    __bashmaster_valid_name "$name" || {
        __bashmaster_error "invalid plugin name: $name"
        return 2
    }
    __bashmaster_plugin_store_safe || return 1
    if ! __bashmaster_installed "$name" && ! __bashmaster_enabled "$name"; then
        __bashmaster_error "plugin '$name' is not installed"
        return 1
    fi
    if [[ -L $link ]]; then
        [[ $(readlink -- "$link") == "../available/$name" ]] || {
            __bashmaster_error "refusing to remove unmanaged plugin link: $link"
            return 1
        }
        rm -- "$link"
        if ! __bashmaster_audit disable "$name"; then
            ln -s -- "../available/$name" "$link"
            __bashmaster_error "could not audit disabling plugin '$name'; disable was rolled back"
            return 1
        fi
    elif [[ -e $link ]]; then
        __bashmaster_error "refusing to remove unmanaged enabled-plugin path: $link"
        return 1
    fi
    __bashmaster_unload_plugin "$name"
}

__bashmaster_trust() {
    local name=$1 file="$BASHMASTER_ROOT/config/trusted.list" temporary backup=
    __bashmaster_valid_name "$name" || {
        __bashmaster_error "invalid plugin name: $name"
        return 2
    }
    __bashmaster_installed "$name" || {
        __bashmaster_error "plugin '$name' is not installed"
        return 1
    }
    __bashmaster_manifest_validate "$BASHMASTER_ROOT/plugins/available/$name" "$name" || return 1
    [[ ! -L $BASHMASTER_ROOT/config && ! -L $file ]] || {
        __bashmaster_error 'refusing to write through a symlinked trust path'
        return 1
    }
    mkdir -p -- "${file%/*}"
    if [[ -f $file ]] && grep -Fqx -- "$name" "$file"; then
        return 0
    fi
    if [[ -f $file ]]; then
        backup=$(umask 077; mktemp "${file}.backup.XXXXXX") || return 1
        if ! cp -p -- "$file" "$backup"; then
            rm -f -- "$backup"
            return 1
        fi
    fi
    temporary=$(umask 077; mktemp "${file}.tmp.XXXXXX") || return 1
    if [[ -f $file ]]; then
        if ! cat -- "$file" > "$temporary"; then
            rm -f -- "$temporary"
            [[ -z $backup ]] || rm -f -- "$backup"
            return 1
        fi
    fi
    printf '%s\n' "$name" >> "$temporary"
    if ! mv -- "$temporary" "$file"; then
        rm -f -- "$temporary"
        [[ -z $backup ]] || rm -f -- "$backup"
        return 1
    fi
    if ! __bashmaster_audit trust "$name"; then
        if [[ -n $backup ]]; then
            mv -- "$backup" "$file" || :
        else
            rm -f -- "$file"
        fi
        __bashmaster_error "could not audit trusting plugin '$name'; trust was rolled back"
        return 1
    fi
    [[ -z $backup ]] || rm -f -- "$backup"
}

__bashmaster_remove_plugin() {
    local name=$1 keep_trust=${2:-0}
    __bashmaster_valid_name "$name" || {
        __bashmaster_error "invalid plugin name: $name"
        return 2
    }
    __bashmaster_installed "$name" || {
        __bashmaster_error "plugin '$name' is not installed"
        return 1
    }
    if [[ $keep_trust != 1 &&
          ( -L $BASHMASTER_ROOT/config || -L $BASHMASTER_ROOT/config/trusted.list ) ]]; then
        __bashmaster_error 'refusing to edit a symlinked trust path'
        return 1
    fi
    __bashmaster_disable "$name" || return 1
    local target="$BASHMASTER_ROOT/plugins/available/$name"
    local temporary="$target.remove.$$"
    [[ ! -e $temporary && ! -L $temporary ]] || {
        __bashmaster_error "temporary removal path already exists: $temporary"
        return 1
    }
    mv -- "$target" "$temporary" || return 1
    if ! __bashmaster_audit remove "$name"; then
        mv -- "$temporary" "$target" || :
        __bashmaster_error "could not audit removing plugin '$name'; removal was rolled back"
        return 1
    fi
    if ! rm -rf -- "$temporary"; then
        mv -- "$temporary" "$target" || :
        __bashmaster_error "could not remove plugin '$name'; attempted rollback"
        return 1
    fi
    if [[ $keep_trust != 1 && -f $BASHMASTER_ROOT/config/trusted.list ]]; then
        local trust_file="$BASHMASTER_ROOT/config/trusted.list"
        [[ ! -L $trust_file ]] || {
            __bashmaster_error 'refusing to edit a symlinked trust list'
            return 1
        }
        local temporary
        temporary=$(umask 077; mktemp "${trust_file}.tmp.XXXXXX") || return 1
        grep -Fvx -- "$name" "$trust_file" > "$temporary" || :
        mv -- "$temporary" "$BASHMASTER_ROOT/config/trusted.list"
    fi
}

__bashmaster_install_plugin() {
    local source_dir=$1 name target temporary
    __bashmaster_plugin_store_safe || return 1
    [[ -d $source_dir ]] || {
        __bashmaster_error "plugin source directory not found: $source_dir"
        return 1
    }
    __bashmaster_manifest_validate "$source_dir" || return 1
    name=${BM_MANIFEST[name]}
    target="$BASHMASTER_ROOT/plugins/available/$name"
    [[ ! -e $target && ! -L $target ]] || {
        __bashmaster_error "plugin '$name' is already installed"
        return 1
    }
    if find "$source_dir" -type l -print -quit | grep -q .; then
        __bashmaster_error 'plugin packages must not contain symbolic links'
        return 1
    fi
    mkdir -p -- "${target%/*}"
    temporary="$target.tmp.$$"
    mkdir -- "$temporary"
    if ! cp -R -- "$source_dir/." "$temporary/"; then
        rm -rf -- "$temporary"
        return 1
    fi
    if ! __bashmaster_manifest_validate "$temporary" "$name"; then
        rm -rf -- "$temporary"
        return 1
    fi
    if ! mv -- "$temporary" "$target"; then
        rm -rf -- "$temporary"
        return 1
    fi
    if ! __bashmaster_audit install "$name"; then
        rm -rf -- "$target"
        __bashmaster_error "could not audit installing plugin '$name'; install was rolled back"
        return 1
    fi
}
