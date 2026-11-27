__bashmaster_audit() {
    local action=$1 plugin=${2:--}
    local root=${BASHMASTER_ROOT:-}
    [[ -n $root ]] || return 1
    [[ ! -L $root/logs && ! -L $root/logs/audit.log ]] || {
        __bashmaster_error 'refusing to write through a symlinked audit path'
        return 1
    }
    (
        umask 077
        mkdir -p -- "$root/logs"
        printf '%s action=%s plugin=%s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$action" "$plugin" \
            >> "$root/logs/audit.log"
    )
}
