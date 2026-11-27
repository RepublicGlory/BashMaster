bm_quickbar_load_entries() {
    local file="$BASHMASTER_ROOT/config/quickbar/config.conf"
    local line label command
    BM_QUICKBAR_LABELS=()
    BM_QUICKBAR_COMMANDS=()
    BM_QUICKBAR_TRUNCATED=0

    [[ -f $file ]] || {
        __bashmaster_error "quickbar config not found: $file"
        return 1
    }
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *'|'* ]] || {
            __bashmaster_error "invalid quickbar entry (expected label|command): $line"
            return 1
        }
        label=${line%%|*}
        command=${line#*|}
        [[ -n $label && -n $command && $line != *$'\033'* ]] || {
            __bashmaster_error 'quickbar entries require a label and command and may not contain escape codes'
            return 1
        }
        if ((${#BM_QUICKBAR_LABELS[@]} == 10)); then
            BM_QUICKBAR_TRUNCATED=1
            continue
        fi
        BM_QUICKBAR_LABELS+=("$label")
        BM_QUICKBAR_COMMANDS+=("$command")
    done < "$file"
}

bm_quickbar_command_quickbar() {
    bm_quickbar_load_entries || return 1
    local count=${#BM_QUICKBAR_LABELS[@]} selected
    if (( count == 0 )); then
        printf 'Quickbar has no configured entries.\n'
        return 0
    fi
    if [[ ! -t 0 || ! -t 1 || $- != *i* ]]; then
        local i
        for ((i = 0; i < count; i++)); do
            printf '%2d. %s\n' "$((i + 1))" "${BM_QUICKBAR_LABELS[i]}"
        done
        (( BM_QUICKBAR_TRUNCATED )) && printf 'Only the first 10 entries are shown.\n'
        return 0
    fi
    selected=$(__bashmaster_ui_select "$count") || return 0
    eval "${BM_QUICKBAR_COMMANDS[selected]}"
}

